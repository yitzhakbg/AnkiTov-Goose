const $ = (id) => document.getElementById(id);

let ws = null;
let reqId = 1;
let activeSession = null;
let loadedSessionIds = new Set();
let sessionsById = new Map();
const originalModes = new Map();
const pending = new Map();
const pendingPerms = new Set();
let currentAgentNode = null;
let currentThoughtNode = null;
let isPromptRunning = false;

function setStatus(s) {
  $("status").textContent = s;
}

function setRunning(running) {
  isPromptRunning = running;
  $("cancelBtn").disabled = !running;
  $("sendBtn").disabled = running;
}

function updateMetaBar(mode, cwd) {
  $("modeBadge").textContent = `mode: ${mode || "—"}`;
  $("cwdBadge").textContent = `cwd: ${cwd || "—"}`;
  $("cwdBadge").title = cwd || "";
}

function setActiveSession(id, mode, cwd) {
  activeSession = id || null;
  const link = $("handoff");
  if (id) {
    link.href = `goose://resume/${encodeURIComponent(id)}`;
    link.setAttribute("aria-disabled", "false");
  } else {
    link.href = "#";
    link.setAttribute("aria-disabled", "true");
  }
  updateMetaBar(mode, cwd);
}

function appendNode(cls, text) {
  const el = document.createElement("div");
  el.className = cls;
  el.textContent = text;
  $("log").appendChild(el);
  $("log").scrollTop = $("log").scrollHeight;
  return el;
}

function rejectAllPending(reason) {
  for (const [, p] of pending) {
    p.reject(new Error(reason));
  }
  pending.clear();
  pendingPerms.clear();
}

function rpc(method, params = {}) {
  return new Promise((resolve, reject) => {
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      return reject(new Error("Not connected"));
    }
    const id = reqId++;
    pending.set(id, { resolve, reject });
    try {
      ws.send(JSON.stringify({ jsonrpc: "2.0", id, method, params }));
    } catch (err) {
      pending.delete(id);
      reject(err);
    }
  });
}

function notify(method, params = {}) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ jsonrpc: "2.0", method, params }));
  }
}

function replyPermission(id, outcome) {
  pendingPerms.delete(id);
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ jsonrpc: "2.0", id, result: { outcome } }));
  }
}

function renderPermissionCard(msg) {
  const { id, params } = msg;
  pendingPerms.add(id);

  const card = document.createElement("div");
  card.className = "perm";

  const title = params.toolCall?.fields?.title || params.toolCall?.title || params.toolCall?.toolCallId || "Tool permission";
  const header = document.createElement("div");
  header.className = "perm-title";
  header.textContent = `Permission required: ${title}`;
  card.appendChild(header);

  const rawInput = params.toolCall?.fields?.rawInput ?? params.toolCall?.rawInput;
  if (rawInput !== undefined) {
    const detail = document.createElement("pre");
    detail.className = "perm-detail";
    detail.textContent = typeof rawInput === "string" ? rawInput : JSON.stringify(rawInput, null, 2);
    card.appendChild(detail);
  }

  const row = document.createElement("div");
  row.className = "row";

  for (const opt of params.options || []) {
    const btn = document.createElement("button");
    btn.textContent = opt.name || opt.optionId;
    btn.onclick = () => {
      replyPermission(id, { outcome: "selected", optionId: opt.optionId });
      card.textContent = `Decision (${title}): ${btn.textContent}`;
    };
    row.appendChild(btn);
  }

  const handoffBtn = document.createElement("button");
  handoffBtn.textContent = "Cancel & Open in Desktop ↗";
  handoffBtn.onclick = () => {
    replyPermission(id, { outcome: "cancelled" });
    card.textContent = `Cancelled in browser — handing off to Goose Desktop`;
    if (activeSession) $("handoff").click();
  };
  row.appendChild(handoffBtn);

  card.appendChild(row);
  $("log").appendChild(card);
  $("log").scrollTop = $("log").scrollHeight;
}

function handleMessage(raw) {
  let msg;
  try {
    msg = JSON.parse(raw);
  } catch {
    return;
  }

  // Response to our RPC request
  if (msg.id !== undefined && !msg.method) {
    const p = pending.get(msg.id);
    if (!p) return;
    pending.delete(msg.id);
    if (msg.error) {
      const detail = msg.error.data ? `${msg.error.message}: ${JSON.stringify(msg.error.data)}` : msg.error.message;
      p.reject(new Error(detail || JSON.stringify(msg.error)));
    } else {
      p.resolve(msg.result);
    }
    return;
  }

  // Agent -> Client request (never auto-approve)
  if (msg.id !== undefined && msg.method === "session/request_permission") {
    renderPermissionCard(msg);
    return;
  }

  // Streamed notifications
  if (msg.method === "session/update") {
    const u = msg.params?.update;
    if (!u) return;
    if (u.sessionUpdate === "agent_message_chunk" && u.content?.type === "text") {
      currentThoughtNode = null;
      if (!currentAgentNode) currentAgentNode = appendNode("msg-agent", "");
      currentAgentNode.textContent += u.content.text;
      $("log").scrollTop = $("log").scrollHeight;
    } else if (u.sessionUpdate === "agent_thought_chunk" && u.content?.type === "text") {
      if (!currentThoughtNode) currentThoughtNode = appendNode("msg-thought", "… ");
      currentThoughtNode.textContent += u.content.text;
      $("log").scrollTop = $("log").scrollHeight;
    } else if (u.sessionUpdate === "user_message_chunk" && u.content?.type === "text") {
      currentAgentNode = null;
      currentThoughtNode = null;
      appendNode("msg-user", `> ${u.content.text}`);
    } else if (u.sessionUpdate === "tool_call") {
      currentAgentNode = null;
      currentThoughtNode = null;
      appendNode("msg-tool", `[tool] ${u.title || u.toolCallId}`);
    } else if (u.sessionUpdate === "tool_call_update" && u.status) {
      appendNode("msg-tool", `[tool ${u.toolCallId}] ${u.status}`);
    } else if (u.sessionUpdate === "current_mode_update" && u.currentModeId) {
      const meta = sessionsById.get(activeSession);
      updateMetaBar(u.currentModeId, meta?.cwd);
    } else if (u.sessionUpdate === "session_info_update" && u.title && activeSession) {
      const opt = Array.from($("sessions").options).find((o) => o.value === activeSession);
      if (opt) opt.textContent = u.title;
    }
  }
}

async function connect() {
  const wsUrl = ($("wsUrl").value || "ws://127.0.0.1:3285/acp").trim();
  const secret = $("secret").value.trim();
  const cwd = $("cwd").value.trim();
  const replayTailRaw = $("replayTail").value.trim();
  const replayTail = replayTailRaw === "" ? 20 : Math.max(0, parseInt(replayTailRaw, 10) || 0);
  await chrome.storage.local.set({ wsUrl, secret, cwd, replayTail });

  if (ws) {
    ws.onclose = null;
    ws.close();
  }
  rejectAllPending("reconnecting");
  loadedSessionIds.clear();
  setRunning(false);
  setStatus("connecting…");

  const url = `${wsUrl}${wsUrl.includes("?") ? "&" : "?"}token=${encodeURIComponent(secret)}`;
  ws = new WebSocket(url);

  ws.onmessage = (e) => handleMessage(e.data);
  ws.onclose = () => {
    setStatus("disconnected");
    setRunning(false);
    rejectAllPending("WebSocket closed");
  };
  ws.onerror = () => setStatus("error (check port 3285, secret & allowed-origin)");

  ws.onopen = async () => {
    try {
      const init = await rpc("initialize", {
        protocolVersion: 1,
        clientCapabilities: {},
        clientInfo: { name: "goose-browser-ext", version: "0.2.0" }
      });
      setStatus("connected");
      $("cfgBox").open = false;
      await refreshSessions(init.agentCapabilities, false);
    } catch (err) {
      setStatus(`init failed: ${err.message}`);
    }
  };
}

async function refreshSessions(caps, autoLoadFirst = false) {
  const sel = $("sessions");
  const prevSelection = sel.value || activeSession;
  sel.innerHTML = "";
  sessionsById.clear();

  try {
    const res = await rpc("session/list", {});
    for (const s of res.sessions || []) {
      sessionsById.set(s.sessionId, s);
      const opt = document.createElement("option");
      opt.value = s.sessionId;
      const dirTail = s.cwd ? ` · ${s.cwd.split("/").filter(Boolean).pop()}` : "";
      opt.textContent = `${s.title || s.sessionId}${dirTail}`;
      sel.appendChild(opt);
    }
  } catch (err) {
    appendNode("msg-warn", `session/list failed: ${err.message}`);
  }

  if (sel.options.length > 0) {
    if (prevSelection && sessionsById.has(prevSelection)) {
      sel.value = prevSelection;
    } else {
      const placeholder = document.createElement("option");
      placeholder.value = "";
      placeholder.textContent = "— Select a session or + New —";
      sel.prepend(placeholder);
      sel.value = "";
      setActiveSession(null, null, null);
    }
    if (autoLoadFirst && sel.value) {
      await loadSession(sel.value);
    }
  } else {
    const opt = document.createElement("option");
    opt.value = "";
    opt.textContent = "No sessions yet — click + New";
    sel.appendChild(opt);
    setActiveSession(null, null, null);
  }
}

async function closePreviousSessionIfLoaded(nextSessionId) {
  if (activeSession && activeSession !== nextSessionId && loadedSessionIds.has(activeSession)) {
    const orig = originalModes.get(activeSession);
    if (orig && orig !== "approve") {
      try {
        await rpc("session/set_mode", { sessionId: activeSession, modeId: orig });
      } catch {
        // Ignore if session cannot restore mode
      }
      originalModes.delete(activeSession);
    }
    try {
      await rpc("session/close", { sessionId: activeSession });
      loadedSessionIds.delete(activeSession);
    } catch {
      // Ignore if server doesn't support or already closed
    }
  }
}

async function enforceApproveMode(sessionId) {
  try {
    await rpc("session/set_mode", { sessionId, modeId: "approve" });
    return "approve";
  } catch (err) {
    appendNode("msg-warn", `Warning: could not force approve mode (${err.message})`);
    return "unknown";
  }
}

async function loadSession(sessionId) {
  if (!sessionId) {
    setActiveSession(null, null, null);
    return;
  }

  const meta = sessionsById.get(sessionId);
  const cwd = meta?.cwd;
  // Bug #2 guard: NEVER fall back to "/" — prepare_session_for_activation updates
  // working_dir in sessions.db whenever passed cwd != session.working_dir!
  if (!cwd) {
    appendNode("msg-warn", `Refusing to load ${sessionId}: missing cwd in session metadata (prevents overwriting working_dir in sessions.db).`);
    return;
  }

  await closePreviousSessionIfLoaded(sessionId);

  $("log").innerHTML = "";
  currentAgentNode = null;
  currentThoughtNode = null;

  const { replayTail = 20 } = await chrome.storage.local.get(["replayTail"]);
  const loadParams = { sessionId, cwd, mcpServers: [] };
  if (Number.isInteger(replayTail) && replayTail > 0) {
    loadParams._meta = { replayTail };
  }

  try {
    const res = await rpc("session/load", loadParams);
    loadedSessionIds.add(sessionId);
    if (res?._meta?.replaySkipped > 0) {
      appendNode("msg-tool", `(Skipped ${res._meta.replaySkipped} earlier messages; showing last ${replayTail}. Open in Desktop ↗ for full thread.)`);
    }
    // Bug #1 fix: session/load restores session.goose_mode from sessions.db (usually "auto").
    // Save original mode so we restore it before close/handoff, then force "approve" here.
    const origMode = res?.modes?.currentModeId;
    if (origMode) originalModes.set(sessionId, origMode);
    const mode = origMode === "approve" ? "approve" : await enforceApproveMode(sessionId);
    setActiveSession(sessionId, mode, cwd);
  } catch (err) {
    appendNode("msg-warn", `session/load failed: ${err.message}`);
  }
}

async function newSession() {
  const cwd = $("cwd").value.trim();
  if (!cwd || !cwd.startsWith("/")) {
    $("cfgBox").open = true;
    return appendNode("msg-warn", "Set an absolute Default cwd (starts with /) in Connection settings first.");
  }

  await closePreviousSessionIfLoaded(null);
  $("log").innerHTML = "";
  currentAgentNode = null;
  currentThoughtNode = null;

  try {
    const res = await rpc("session/new", { cwd, mcpServers: [] });
    const id = res.sessionId;
    loadedSessionIds.add(id);
    sessionsById.set(id, { sessionId: id, cwd, title: `New (${id.slice(0, 8)})` });

    const sel = $("sessions");
    const opt = document.createElement("option");
    opt.value = id;
    opt.textContent = `New (${id.slice(0, 8)})`;
    sel.prepend(opt);
    sel.value = id;

    const mode = res.modes?.currentModeId || await enforceApproveMode(id);
    setActiveSession(id, mode, cwd);
  } catch (err) {
    appendNode("msg-warn", `session/new failed: ${err.message}`);
  }
}

async function sendPrompt() {
  const text = $("prompt").value.trim();
  if (!text || isPromptRunning) return;
  if (!activeSession) await newSession();
  if (!activeSession) return;

  $("prompt").value = "";
  currentAgentNode = null;
  currentThoughtNode = null;
  appendNode("msg-user", `> ${text}`);
  setRunning(true);

  try {
    const res = await rpc("session/prompt", {
      sessionId: activeSession,
      prompt: [{ type: "text", text }]
    });
    if (res?.stopReason && res.stopReason !== "end_turn") {
      appendNode("msg-tool", `[stopped: ${res.stopReason}]`);
    }
  } catch (err) {
    appendNode("msg-warn", `Prompt error: ${err.message}`);
  } finally {
    setRunning(false);
  }
}

function insertClip({ title, url, selection }) {
  const parts = [`Page: ${title} (${url})`];
  if (selection) parts.push(`Selection:\n"""\n${selection}\n"""`);
  const box = $("prompt");
  box.value = `${parts.join("\n")}\n\n${box.value}`;
  box.focus();
}

$("handoff").addEventListener("click", (e) => {
  if (!activeSession) return;
  const orig = originalModes.get(activeSession);
  if (orig && orig !== "approve" && ws && ws.readyState === WebSocket.OPEN) {
    e.preventDefault();
    const href = $("handoff").href;
    rpc("session/set_mode", { sessionId: activeSession, modeId: orig })
      .catch(() => {})
      .finally(() => {
        originalModes.delete(activeSession);
        // Navigate in a hidden/auto-closing helper or direct window.open after async restore
        window.open(href, "_blank");
      });
  }
});

$("connectBtn").onclick = connect;
$("refreshBtn").onclick = () => refreshSessions(null, false);
$("newBtn").onclick = newSession;
$("sendBtn").onclick = sendPrompt;
$("sessions").onchange = (e) => loadSession(e.target.value);

$("cancelBtn").onclick = () => {
  for (const id of pendingPerms) replyPermission(id, { outcome: "cancelled" });
  if (activeSession) notify("session/cancel", { sessionId: activeSession });
};

$("tabBtn").onclick = async () => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tab) insertClip({ title: tab.title || "", url: tab.url || "", selection: "" });
};

$("prompt").addEventListener("keydown", (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === "Enter") sendPrompt();
});

chrome.storage.onChanged.addListener((changes, area) => {
  if (area === "session" && changes.pendingClip?.newValue) {
    insertClip(changes.pendingClip.newValue);
    chrome.storage.session.remove("pendingClip");
  }
});

(async () => {
  const cfg = await chrome.storage.local.get(["wsUrl", "secret", "cwd", "replayTail"]);
  $("wsUrl").value = cfg.wsUrl || "ws://127.0.0.1:3285/acp";
  $("secret").value = cfg.secret || "";
  $("cwd").value = cfg.cwd || "/Volumes/YBG1TB4Mac/AnkiTov-C";
  $("replayTail").value = cfg.replayTail !== undefined ? String(cfg.replayTail) : "20";

  if (cfg.secret) {
    connect();
  } else {
    $("cfgBox").open = true;
  }

  const { pendingClip } = await chrome.storage.session.get("pendingClip");
  if (pendingClip) {
    insertClip(pendingClip);
    chrome.storage.session.remove("pendingClip");
  }
})();
