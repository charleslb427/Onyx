// =====================================
// Onyx – content.js (Instagram Filter)
// =====================================

// ---------- CONFIG ----------
let config = {
  reels: true,
  explore: true,
  ads: true
};

// ---------- LOAD CONFIG ----------
chrome.storage.sync.get(config, saved => {
  config = { ...config, ...saved };
  updateCSS();
  syncPanel();
});

// ---------- WATCH CONFIG ----------
chrome.storage.onChanged.addListener(() => {
  chrome.storage.sync.get(config, saved => {
    config = { ...config, ...saved };
    updateCSS();
    syncPanel();
  });
});

// ---------- CONTEXT ----------
function isInMessages() {
  return location.pathname.startsWith("/direct");
}
function isInReelsPage() {
  return location.pathname.startsWith("/reels");
}

// ---------- REDIRECT ----------
function redirectIfReelsBlocked() {
  if (config.reels && isInReelsPage()) {
    location.replace("https://www.instagram.com/");
  }
}

// ---------- CSS FILTERS ----------
const style = document.createElement("style");
style.id = "onyx-style";
document.documentElement.appendChild(style);

function updateCSS() {
  redirectIfReelsBlocked();

  if (isInMessages()) {
    style.textContent = "";
    return;
  }

  let css = "";
  if (config.reels) css += `a[href*="/reels/"]{display:none!important;}`;
  if (config.explore) css += `a[href="/explore/"]{display:none!important;}`;
  if (config.ads) {
    css += `
      article:has(span:contains("Sponsorisé")),
      article:has(span:contains("Sponsored")){display:none!important;}
    `;
  }

  style.textContent = css;
}

// ---------- PANEL ----------
function createPanel() {
  if (document.getElementById("onyx-overlay")) return;

  const overlay = document.createElement("div");
  overlay.id = "onyx-overlay";
  Object.assign(overlay.style, {
    position: "fixed",
    inset: "0",
    background: "rgba(0,0,0,0.35)",
    zIndex: 9999,
    display: "none",
    backdropFilter: "blur(2px)"
  });

  overlay.innerHTML = `
    <div id="onyx-panel" style="
      background:#fff;
      max-width:360px;
      margin:80px auto;
      padding:20px;
      border-radius:18px;
      font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial,sans-serif;
      box-shadow:0 10px 40px rgba(0,0,0,.25);
      transform:translateY(20px) scale(.96);
      opacity:0;
      transition:transform .18s ease, opacity .18s ease;
    ">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:16px;">
        <strong style="font-size:18px;">Onyx</strong>
        <span id="onyx-close" style="font-size:22px;cursor:pointer;">✕</span>
      </div>

      ${optionRow("Reels", "onyx-reels")}
      ${optionRow("Explorer", "onyx-explore")}
      ${optionRow("Publicités", "onyx-ads")}

      <div style="margin-top:16px;font-size:12px;color:#777;">
        Application indépendante, non affiliée à Meta.
      </div>
    </div>
  `;

  document.body.appendChild(overlay);

  overlay.onclick = e => {
    if (e.target === overlay) hidePanel();
  };
  overlay.querySelector("#onyx-close").onclick = hidePanel;

  overlay.querySelector("#onyx-reels").onchange = e => save("reels", e.target.checked);
  overlay.querySelector("#onyx-explore").onchange = e => save("explore", e.target.checked);
  overlay.querySelector("#onyx-ads").onchange = e => save("ads", e.target.checked);
}

// ---------- OPTION ROW ----------
function optionRow(label, id) {
  return `
    <div class="onyx-row">
      <div>
        <div class="onyx-label">${label}</div>
        <div class="onyx-state" id="${id}-state"></div>
      </div>
      <label class="onyx-switch">
        <input type="checkbox" id="${id}">
        <span class="onyx-slider"></span>
      </label>
    </div>
  `;
}

// ---------- SWITCH & ROW CSS ----------
const uiStyle = document.createElement("style");
uiStyle.textContent = `
.onyx-row{
  display:flex;
  justify-content:space-between;
  align-items:center;
  padding:12px 0;
  border-bottom:1px solid #eee;
}
.onyx-label{
  font-size:15px;
}
.onyx-state{
  font-size:12px;
  color:#777;
}
.onyx-row.off .onyx-label{
  opacity:.6;
}

.onyx-switch{
  position:relative;
  width:42px;
  height:24px;
}
.onyx-switch input{display:none;}
.onyx-slider{
  position:absolute;
  inset:0;
  background:#ccc;
  border-radius:24px;
  transition:.2s;
}
.onyx-slider:before{
  content:"";
  position:absolute;
  width:18px;
  height:18px;
  left:3px;
  top:3px;
  background:#fff;
  border-radius:50%;
  transition:.2s;
}
.onyx-switch input:checked + .onyx-slider{
  background:#0095f6;
}
.onyx-switch input:checked + .onyx-slider:before{
  transform:translateX(18px);
}
`;
document.documentElement.appendChild(uiStyle);

// ---------- PANEL CONTROL ----------
function showPanel() {
  const overlay = document.getElementById("onyx-overlay");
  const panel = document.getElementById("onyx-panel");
  overlay.style.display = "block";
  requestAnimationFrame(() => {
    panel.style.opacity = "1";
    panel.style.transform = "translateY(0) scale(1)";
  });
}

function hidePanel() {
  const overlay = document.getElementById("onyx-overlay");
  const panel = document.getElementById("onyx-panel");
  panel.style.opacity = "0";
  panel.style.transform = "translateY(20px) scale(.96)";
  setTimeout(() => {
    overlay.style.display = "none";
  }, 180);
}

// ---------- SYNC UI ----------
function syncPanel() {
  syncOption("onyx-reels", config.reels);
  syncOption("onyx-explore", config.explore);
  syncOption("onyx-ads", config.ads);
}

function syncOption(id, enabled) {
  const input = document.getElementById(id);
  const state = document.getElementById(id + "-state");
  const row = input?.closest(".onyx-row");

  if (!input || !state || !row) return;

  input.checked = enabled;
  state.textContent = enabled ? "Masqué" : "Visible";
  row.classList.toggle("off", !enabled);
}

// ---------- SAVE ----------
function save(key, value) {
  chrome.storage.sync.set({ [key]: value });
}

// ---------- FLOAT BUTTON ----------
function createButton() {
  if (document.getElementById("onyx-button")) return;

  const btn = document.createElement("div");
  btn.id = "onyx-button";
  btn.textContent = "⚙︎";

  Object.assign(btn.style, {
    position: "fixed",
    right: "16px",
    bottom: "96px",
    width: "42px",
    height: "42px",
    borderRadius: "50%",
    background: "rgba(255,255,255,.95)",
    boxShadow: "0 4px 14px rgba(0,0,0,.25)",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    fontSize: "18px",
    cursor: "pointer",
    zIndex: 9999
  });

  btn.onclick = showPanel;
  document.body.appendChild(btn);
}

// ---------- OBSERVER ----------
function start() {
  if (!document.body) {
    requestAnimationFrame(start);
    return;
  }

  createPanel();
  createButton();
  updateCSS();

  new MutationObserver(() => {
    createPanel();
    createButton();
    updateCSS();
  }).observe(document.body, { childList: true, subtree: true });
}

start();
