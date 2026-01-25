const defaults = {
  reels: true,
  explore: true,
  ads: true
};

const inputs = ["reels", "explore", "ads"];

chrome.storage.sync.get(defaults, config => {
  inputs.forEach(key => {
    document.getElementById(key).checked = config[key];
  });
});

inputs.forEach(key => {
  document.getElementById(key).addEventListener("change", e => {
    chrome.storage.sync.set({ [key]: e.target.checked });
  });
});
