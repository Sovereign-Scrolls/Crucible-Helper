function buildMenu(ui, email) {
  // PC Manager menu (visible to everyone)
  const pcMenu = ui.createMenu("PC Manager")
    //.addItem("Setup PC Sheet", "openPCSheetDialog")
    .addItem("Upload PC JSON", "openFirebaseUploadDialog")
    .addItem("Import Logistics Data", "promptCharacterNumber")
    .addItem("Verify PC", "promptVerifyCharacter")
    .addSeparator()
    .addItem("Upload Rules JSON", "uploadRulesJson");

  pcMenu.addToUi();

  // Character Tools menu (visible only to specific staff)
  const staffEmails = ["jbrite504@gmail.com"];

  if (staffEmails.includes(email)) {
    ui.createMenu("Character Tools")
      .addItem("Upload All Characters", "uploadAllCharacters")
      .addToUi();
  }
}

function openPCSheetDialog() {
  const html = HtmlService.createHtmlOutputFromFile('setupPCSheetDialog')
    .setWidth(400)
    .setHeight(250);
  SpreadsheetApp.getUi().showModalDialog(html, 'Setup PC Sheet');
}

function openFirebaseUploadDialog() {
  const html = HtmlService.createHtmlOutputFromFile('uploadToFirebaseDialog')
    .setWidth(400)
    .setHeight(250);
  SpreadsheetApp.getUi().showModalDialog(html, 'Manual Upload to Firebase');
}

