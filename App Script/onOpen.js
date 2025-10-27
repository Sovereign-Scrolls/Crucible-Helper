function onOpen() {
  const ui = SpreadsheetApp.getUi();
  const email = Session.getActiveUser().getEmail();

  buildMenu(ui, email);
  populateEditorList();
}