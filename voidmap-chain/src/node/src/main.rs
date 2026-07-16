//! Voidmap native chain node — plain TCP networking + φ-PoW mining.
//!
//! Commands:
//!   keygen                 generate a node keypair, print address
//!   query                  print chain + ledger stats from disk
//!   mine [--blocks N]      mine N blocks locally (no networking)
//!   run [--listen ADDR] [--peer ADDR]... [--no-mine]
//!                          join the TCP network, sync, and (optionally) mine

use clap::{Parser, Subcommand};
use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{broadcast, Mutex};

use voidmap_core::{Block, Hash, Tx, MICRO};
use voidmap_crypto::{verify, KeyPair, PublicKey};
use voidmap_network::{candidate_header, read_json, write_json, ChainStore, NetMsg};
use voidmap_pow::{adjust_difficulty, mine, TARGET_BLOCK_MS};

const GENESIS_DEV_SEED: [u8; 32] = [7u8; 32];
const GENESIS_DAO_SEED: [u8; 32] = [9u8; 32];
const INITIAL_DIFFICULTY: u64 = 1000;
const SYNC_INTERVAL: Duration = Duration::from_secs(10);

#[derive(Parser)]
#[command(name = "voidmap-node", about = "Voidmap native chain node")]
struct Cli {
    #[arg(long, default_value = "./voidmap-data")]
    data_dir: PathBuf,
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    Keygen,
    Query,
    Mine {
        #[arg(long, default_value_t = 1)]
        blocks: u64,
    },
    Run {
        #[arg(long, default_value_t = 7000)]
        listen: u16,
        #[arg(long)]
        peer: Vec<String>,
        #[arg(long, default_value_t = false)]
        no_mine: bool,
    },
}

#[derive(serde::Serialize, serde::Deserialize)]
struct SavedChain {
    blocks: Vec<Block>,
}

// ── key / store persistence ────────────────────────────────────────────────

fn load_or_create_key(data_dir: &std::path::Path) -> KeyPair {
    let path = data_dir.join("key.json");
    if path.exists() {
        let seed: [u8; 32] =
            serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
        return KeyPair::from_seed(seed);
    }
    std::fs::create_dir_all(data_dir).ok();
    let kp = KeyPair::generate();
    let seed = kp.secret_key_bytes();
    std::fs::write(&path, serde_json::to_string(&seed).unwrap()).ok();
    kp
}

fn load_store(data_dir: &std::path::Path) -> ChainStore {
    let dev = KeyPair::from_seed(GENESIS_DEV_SEED).address();
    let dao = KeyPair::from_seed(GENESIS_DAO_SEED).address();
    let mut store = ChainStore::new(dev, dao, INITIAL_DIFFICULTY);
    let path = data_dir.join("chain.json");
    if path.exists() {
        let saved: SavedChain =
            serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
        store.adopt(&saved.blocks).ok();
    }
    store
}

fn save_store(data_dir: &std::path::Path, store: &ChainStore) {
    std::fs::create_dir_all(data_dir).ok();
    let saved = SavedChain {
        blocks: store.canonical_blocks(),
    };
    std::fs::write(
        data_dir.join("chain.json"),
        serde_json::to_string_pretty(&saved).unwrap(),
    )
    .ok();
}

// ── mempool ────────────────────────────────────────────────────────────────

struct Mempool {
    pending: Vec<Tx>,
    seen: HashSet<Hash>,
}

impl Mempool {
    fn new() -> Self {
        Mempool {
            pending: Vec::new(),
            seen: HashSet::new(),
        }
    }

    fn validate(&self, tx: &Tx, store: &ChainStore) -> Result<(), String> {
        match tx {
            Tx::SubmitWork {
                miner,
                task_id,
                result_commit,
                quality,
                timing_ms,
                fee,
                sig,
            } => {
                let pk = PublicKey::from_bytes(*miner.as_bytes());
                if !verify(&pk, &tx.signing_bytes(), sig) {
                    return Err("bad signature".into());
                }
                if *quality > 100 {
                    return Err("quality > 100".into());
                }
                let _ = (task_id, result_commit, timing_ms, fee, store);
                Ok(())
            }
            _ => Err("unknown tx type".into()),
        }
    }

    fn add(&mut self, tx: Tx, store: &ChainStore) -> Result<(), String> {
        let h = tx.hash();
        if self.seen.contains(&h) {
            return Err("duplicate".into());
        }
        self.validate(&tx, store)?;
        self.seen.insert(h);
        self.pending.push(tx);
        Ok(())
    }

    fn remove_included(&mut self, txs: &[Tx]) {
        for tx in txs {
            let h = tx.hash();
            self.seen.remove(&h);
        }
        self.pending.retain(|tx| !txs.iter().any(|t| t.hash() == tx.hash()));
    }

    fn drain(&mut self) -> Vec<Tx> {
        let txs: Vec<Tx> = self.pending.drain(..).collect();
        self.seen.clear();
        txs
    }
}

// ── helpers ────────────────────────────────────────────────────────────────

fn demo_submit(kp: &KeyPair, task_id: u32, quality: u16) -> Tx {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    let commit_bytes: [u8; 32] = rng.gen();
    let result_commit = Hash::from_bytes(commit_bytes);
    let timing_ms: u64 = 2000 + rng.gen_range(0..8000);
    let mut tx = Tx::SubmitWork {
        miner: kp.address(),
        task_id,
        result_commit,
        quality,
        timing_ms,
        fee: 0,
        sig: voidmap_crypto::Sig::from_bytes([0u8; 64]),
    };
    let sig = kp.sign(&tx.signing_bytes());
    if let Tx::SubmitWork { sig: s, .. } = &mut tx {
        *s = sig;
    }
    tx
}

// ── command handlers ───────────────────────────────────────────────────────

fn keygen() {
    let kp = KeyPair::generate();
    println!("seed: {}", hex::encode(kp.secret_key_bytes()));
    println!("address: {}", kp.address());
}

fn query(data_dir: &std::path::Path) {
    let store = load_store(data_dir);
    let state = store.replay_to(&store.best);
    println!("blocks: {}", store.canonical_blocks().len());
    println!("submissions: {}", state.total_submissions);
    println!("total minted: {} VOID", state.total_mined_micro / MICRO);
    println!(
        "dev fund: {} VOID | dao: {} VOID",
        state.balance(&KeyPair::from_seed(GENESIS_DEV_SEED).address()) / MICRO,
        state.balance(&KeyPair::from_seed(GENESIS_DAO_SEED).address()) / MICRO,
    );
    println!("avg network quality: {}", state.avg_network_quality());
    println!("best height: {}", store.best_tip().header.height);
}

fn mine_single(data_dir: &std::path::Path, target_blocks: u64) {
    let miner_kp = load_or_create_key(data_dir);
    let mut store = load_store(data_dir);
    if store.canonical_blocks().is_empty() {
        let dev = KeyPair::from_seed(GENESIS_DEV_SEED).address();
        let dao = KeyPair::from_seed(GENESIS_DAO_SEED).address();
        let genesis = voidmap_core::genesis_block(dev, dao, INITIAL_DIFFICULTY);
        store.adopt(&[genesis]).expect("genesis adopt");
    }

    let start_height = store.canonical_blocks().len() as u64;
    let mut mined = 0u64;
    while mined < target_blocks {
        let tip = store.canonical_blocks().last().cloned().unwrap();
        let tip_hash = tip.hash();
        let parent_state = store.replay_to(&tip_hash);
        let now = voidmap_core::now_ms();
        let difficulty = adjust_difficulty(
            tip.header.difficulty,
            now.saturating_sub(tip.header.timestamp_ms),
            TARGET_BLOCK_MS,
        );
        let mut header = voidmap_core::BlockHeader {
            version: 1,
            height: tip.header.height + 1,
            timestamp_ms: now,
            parent: tip_hash,
            state_root: voidmap_crypto::Hash::zero(),
            tx_root: voidmap_crypto::Hash::zero(),
            difficulty,
            nonce: 0,
            miner: miner_kp.address(),
        };
        let tentative = Block {
            header: header.clone(),
            txs: vec![],
        };
        let next_state = parent_state.execute(&tentative).expect("tentative exec");
        header.state_root = next_state.state_root();

        let t0 = std::time::Instant::now();
        let mined_block = mine(header.clone(), difficulty, u64::MAX);
        let elapsed = t0.elapsed();
        let (nonce, _) = match mined_block {
            Some(x) => x,
            None => continue,
        };
        header.nonce = nonce;
        let block = Block {
            header,
            txs: vec![],
        };
        if store.add_block(block).is_err() {
            continue;
        }
        mined += 1;
        println!(
            "block #{:>4} nonce={:>12} height={} elapsed={}ms difficulty={}",
            start_height + mined,
            nonce,
            start_height + mined,
            elapsed.as_millis(),
            difficulty
        );
        save_store(data_dir, &store);
    }
    println!(
        "mined {} blocks; total submissions = {}",
        mined,
        store.replay_to(&store.best).total_submissions
    );
}

// ── TCP networking ─────────────────────────────────────────────────────────

async fn peer_read(stream: &mut TcpStream) -> std::io::Result<NetMsg> {
    read_json(stream).await
}

async fn peer_write(stream: &mut TcpStream, msg: &NetMsg) -> std::io::Result<()> {
    write_json(stream, msg).await
}

/// Reader task: reads messages from a peer, updates local store/mempool, logs.
async fn spawn_reader(
    mut stream: TcpStream,
    addr: std::net::SocketAddr,
    store: Arc<Mutex<ChainStore>>,
    mempool: Arc<Mutex<Mempool>>,
    data_dir: PathBuf,
    broadcast_tx: broadcast::Sender<NetMsg>,
) {
    loop {
        let msg = match peer_read(&mut stream).await {
            Ok(m) => m,
            Err(e) => {
                eprintln!("[net] reader {} disconnected: {}", addr, e);
                return;
            }
        };
        match msg {
            NetMsg::Block(b) => {
                let hash = b.hash();
                let mut s = store.lock().await;
                match s.add_block(b.clone()) {
                    Ok(true) => {
                        let tip = s.best_tip();
                        save_store(&data_dir, &s);
                        println!("[net] synced block {} height={}", &hash, tip.header.height);
                        // Remove included txs from mempool.
                        drop(s);
                        mempool.lock().await.remove_included(&b.txs);
                        // Gossip to other peers.
                        let _ = broadcast_tx.send(NetMsg::Block(b));
                    }
                    Ok(false) => {}
                    Err(e) => {
                        let h = s.best_tip().header.height;
                        eprintln!("[net] block rejected from {}: {} (tip {})", addr, e, h);
                    }
                }
            }
            NetMsg::Tx(tx) => {
                let tx_hash = tx.hash();
                let mut pool = mempool.lock().await;
                let s = store.lock().await;
                match pool.add(tx.clone(), &s) {
                    Ok(()) => {
                        println!("[net] mempool +1 tx {} (pool={})", &tx_hash, pool.pending.len());
                        drop(pool);
                        drop(s);
                        let _ = broadcast_tx.send(NetMsg::Tx(tx));
                    }
                    Err(e) => {
                        eprintln!("[net] tx rejected from {}: {}", addr, e);
                    }
                }
            }
            NetMsg::SyncRequest | NetMsg::SyncResponse(_) => {}
        }
    }
}

/// Writer task: subscribes to broadcast channel, writes every message to the peer.
async fn spawn_writer(
    mut stream: TcpStream,
    addr: std::net::SocketAddr,
    mut rx: broadcast::Receiver<NetMsg>,
) {
    while let Ok(msg) = rx.recv().await {
        if peer_write(&mut stream, &msg).await.is_err() {
            eprintln!("[net] writer {} failed, dropping", addr);
            return;
        }
    }
}

/// Open a short-lived sync connection to a peer and adopt their chain.
async fn sync_with_peer(
    peer_addr: &str,
    store: &Arc<Mutex<ChainStore>>,
    data_dir: &PathBuf,
) {
    if let Ok(mut stream) = TcpStream::connect(peer_addr).await {
        let _ = stream.write_all(&[0x02]).await;
        let _ = peer_write(&mut stream, &NetMsg::SyncRequest).await;
        if let Ok(NetMsg::SyncResponse(chain)) = peer_read(&mut stream).await {
            let mut s = store.lock().await;
            if s.adopt(&chain).unwrap_or(false) {
                let tip = s.best_tip();
                save_store(data_dir, &s);
                println!(
                    "[sync] from {} — height {} ({} blocks)",
                    peer_addr,
                    tip.header.height,
                    chain.len()
                );
            }
        }
    }
}

async fn run_network(
    data_dir: PathBuf,
    listen_port: u16,
    peers: Vec<String>,
    do_mine: bool,
) {
    let miner_kp = load_or_create_key(&data_dir);
    let miner_addr = miner_kp.address();
    let store = Arc::new(Mutex::new(load_store(&data_dir)));
    let mempool = Arc::new(Mutex::new(Mempool::new()));
    let (broadcast_tx, _) = broadcast::channel::<NetMsg>(256);

    // Ensure genesis exists.
    {
        let mut s = store.lock().await;
        if s.canonical_blocks().is_empty() {
            let dev = KeyPair::from_seed(GENESIS_DEV_SEED).address();
            let dao = KeyPair::from_seed(GENESIS_DAO_SEED).address();
            let genesis = voidmap_core::genesis_block(dev, dao, INITIAL_DIFFICULTY);
            s.adopt(&[genesis]).expect("genesis adopt");
        }
    }

    let listen_addr = format!("0.0.0.0:{}", listen_port);
    let listener = TcpListener::bind(&listen_addr).await.expect("bind");
    println!(
        "[net] listening on {} (mining: {})",
        listen_addr,
        if do_mine { "on" } else { "off" }
    );

    // Connect to each --peer on startup (client-initiated persistent connections).
    for peer_addr in &peers {
        match TcpStream::connect(peer_addr).await {
            Ok(mut stream) => {
                eprintln!("[net] connected to {}", peer_addr);
                let a: std::net::SocketAddr = peer_addr.parse().unwrap();
                stream.write_all(&[0x01]).await.unwrap();
                let std_stream = stream.into_std().unwrap();
                let std_stream2 = std_stream.try_clone().unwrap();
                let reader_stream = TcpStream::from_std(std_stream).unwrap();
                let writer_stream = TcpStream::from_std(std_stream2).unwrap();
                let rx = broadcast_tx.subscribe();
                tokio::spawn(spawn_reader(
                    reader_stream,
                    a,
                    store.clone(),
                    mempool.clone(),
                    data_dir.clone(),
                    broadcast_tx.clone(),
                ));
                tokio::spawn(spawn_writer(writer_stream, a, rx));
            }
            Err(e) => {
                eprintln!("[net] failed to connect to {}: {}", peer_addr, e);
            }
        }
    }

    // Initial sync via short-lived connections.
    for peer_addr in &peers {
        sync_with_peer(peer_addr, &store, &data_dir).await;
    }

    // Accept incoming connections (server side).
    let server_store = store.clone();
    let server_mempool = mempool.clone();
    let server_data = data_dir.clone();
    let server_bcast = broadcast_tx.clone();
    tokio::spawn(async move {
        loop {
            match listener.accept().await {
                Ok((mut stream, addr)) => {
                    let mut proto = [0u8; 1];
                    if stream.read_exact(&mut proto).await.is_err() {
                        eprintln!("[net] {} protocol read failed", addr);
                        continue;
                    }
                    match proto[0] {
                        0x01 => {
                            eprintln!("[net] persistent connection from {}", addr);
                            let std_stream = stream.into_std().unwrap();
                            let std_stream2 = std_stream.try_clone().unwrap();
                            let reader_stream = TcpStream::from_std(std_stream).unwrap();
                            let writer_stream = TcpStream::from_std(std_stream2).unwrap();
                            let rx = server_bcast.subscribe();
                            tokio::spawn(spawn_reader(
                                reader_stream,
                                addr,
                                server_store.clone(),
                                server_mempool.clone(),
                                server_data.clone(),
                                server_bcast.clone(),
                            ));
                            tokio::spawn(spawn_writer(writer_stream, addr, rx));
                        }
                        0x02 => {
                            if let Ok(NetMsg::SyncRequest) = peer_read(&mut stream).await {
                                let chain = server_store.lock().await.canonical_blocks();
                                let _ = peer_write(&mut stream, &NetMsg::SyncResponse(chain)).await;
                            }
                        }
                        other => {
                            eprintln!("[net] {} unknown protocol byte: {}", addr, other);
                        }
                    }
                }
                Err(e) => eprintln!("[net] accept error: {}", e),
            }
        }
    });

    // ── miner task ─────────────────────────────────────────────────────────
    let miner_store = store.clone();
    let miner_mempool = mempool.clone();
    let kp = miner_kp.clone();
    let miner_bcast = broadcast_tx.clone();
    let miner_data = data_dir.clone();
    if do_mine {
        tokio::spawn(async move {
            use rand::Rng;
            eprintln!("[miner] task started, mining as {}", miner_addr);
            loop {
                let (header_template, block_txs) = {
                    let s = miner_store.lock().await;
                    let tip = s.best_tip();
                    let parent_state = s.replay_to(&tip.hash());
                    let now = voidmap_core::now_ms();
                    let elapsed = now.saturating_sub(tip.header.timestamp_ms);
                    let difficulty =
                        adjust_difficulty(tip.header.difficulty, elapsed, TARGET_BLOCK_MS);

                    // Grab a demo submit + mempool txs.
                    let quality: u16 = 70 + rand::thread_rng().gen_range(0..26);
                    let submit = demo_submit(&kp, 1, quality);
                    let mut all_txs = vec![submit];

                    // Include mempool txs.
                    {
                        let mut pool = miner_mempool.lock().await;
                        let mempool_txs = pool.drain();
                        all_txs.extend(mempool_txs);
                    }

                    let tx_root = {
                        let mut buf = Vec::new();
                        for t in &all_txs {
                            buf.extend_from_slice(t.hash().as_bytes());
                        }
                        Hash::digest(&buf)
                    };
                    let mut candidate = voidmap_core::Block {
                        header: candidate_header(
                            &s,
                            miner_addr,
                            difficulty,
                            tx_root,
                            Hash::zero(),
                            now,
                        ),
                        txs: all_txs.clone(),
                    };
                    let next = parent_state.execute(&candidate).expect("exec");
                    candidate.header.state_root = next.state_root();
                    (candidate.header, candidate.txs)
                };

                let header_for_mine = header_template.clone();
                let diff_for_mine = header_template.difficulty;
                let mine_result = tokio::task::spawn_blocking(move || {
                    mine(header_for_mine, diff_for_mine, u64::MAX)
                }).await.unwrap();
                if let Some((nonce, _)) = mine_result {
                    let mut header = header_template;
                    header.nonce = nonce;
                    let block = Block {
                        header,
                        txs: block_txs,
                    };
                    let accepted = {
                        let mut s = miner_store.lock().await;
                        s.add_block(block.clone()).ok()
                    };
                    if accepted == Some(true) {
                        // Remove included txs from mempool.
                        miner_mempool
                            .lock()
                            .await
                            .remove_included(&block.txs);
                        let s = miner_store.lock().await;
                        let tip = s.best_tip();
                        save_store(&miner_data, &s);
                        println!(
                            "[mine] height {} difficulty={} txs={}",
                            tip.header.height,
                            tip.header.difficulty,
                            block.txs.len()
                        );
                        let _ = miner_bcast.send(NetMsg::Block(block));
                    }
                }
                tokio::time::sleep(Duration::from_millis(50)).await;
            }
        });
    }

    // ── periodic re-sync task ──────────────────────────────────────────────
    let sync_store = store.clone();
    let sync_data = data_dir.clone();
    let sync_peers = peers.clone();
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(SYNC_INTERVAL).await;
            for peer_addr in &sync_peers {
                sync_with_peer(peer_addr, &sync_store, &sync_data).await;
            }
        }
    });

    // ── main event loop (idle — all work is in spawned tasks) ──────────────
    loop {
        tokio::time::sleep(Duration::from_secs(60)).await;
    }
}

// ── entry point ────────────────────────────────────────────────────────────

#[tokio::main]
async fn main() {
    let cli = Cli::parse();
    match cli.command {
        Command::Keygen => keygen(),
        Command::Query => query(&cli.data_dir),
        Command::Mine { blocks } => mine_single(&cli.data_dir, blocks),
        Command::Run {
            listen,
            peer,
            no_mine,
        } => run_network(cli.data_dir, listen, peer, !no_mine).await,
    }
}
