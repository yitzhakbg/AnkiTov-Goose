function ensureSetup() {
  chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: true });
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: "send-to-goose",
      title: "Send selection / page to Goose",
      contexts: ["selection", "page"]
    });
  });
}

chrome.runtime.onInstalled.addListener(ensureSetup);
chrome.runtime.onStartup.addListener(ensureSetup);

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId !== "send-to-goose" || !tab) return;
  await chrome.sidePanel.open({ windowId: tab.windowId });
  await chrome.storage.session.set({
    pendingClip: {
      title: tab.title || "",
      url: tab.url || "",
      selection: info.selectionText || "",
      ts: Date.now()
    }
  });
});
