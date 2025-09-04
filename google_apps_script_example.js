// Google Apps Script to handle Firebase Function requests
// Deploy this as a web app in Google Apps Script

function doPost(e) {
  try {
    // Parse the incoming data
    const data = JSON.parse(e.postData.contents);
    
    // Extract parameters
    const action = data.action;
    const spreadsheetId = data.spreadsheetId;
    const sheetName = data.sheetName;
    const rowData = data.data;
    const timestamp = data.timestamp;
    const userId = data.userId;
    
    // Validate required fields
    if (!action || !spreadsheetId || !sheetName || !rowData) {
      return ContentService
        .createTextOutput(JSON.stringify({ 
          success: false, 
          error: 'Missing required fields' 
        }))
        .setMimeType(ContentService.MimeType.JSON);
    }
    
    // Get the spreadsheet and sheet
    const spreadsheet = SpreadsheetApp.openById(spreadsheetId);
    const sheet = spreadsheet.getSheetByName(sheetName);
    
    if (!sheet) {
      return ContentService
        .createTextOutput(JSON.stringify({ 
          success: false, 
          error: 'Sheet not found' 
        }))
        .setMimeType(ContentService.MimeType.JSON);
    }
    
    // Handle different actions
    switch (action) {
      case 'appendRow':
        // Add timestamp and userId to the data
        const fullRowData = [timestamp, userId, ...rowData];
        
        // Append the row
        sheet.appendRow(fullRowData);
        
        return ContentService
          .createTextOutput(JSON.stringify({ 
            success: true, 
            message: 'Row appended successfully',
            rowData: fullRowData
          }))
          .setMimeType(ContentService.MimeType.JSON);
        
      case 'updateCell':
        // Example: Update a specific cell
        const row = data.row;
        const col = data.col;
        const value = data.value;
        
        sheet.getRange(row, col).setValue(value);
        
        return ContentService
          .createTextOutput(JSON.stringify({ 
            success: true, 
            message: 'Cell updated successfully' 
          }))
          .setMimeType(ContentService.MimeType.JSON);
        
      default:
        return ContentService
          .createTextOutput(JSON.stringify({ 
            success: false, 
            error: 'Unknown action' 
          }))
          .setMimeType(ContentService.MimeType.JSON);
    }
    
  } catch (error) {
    return ContentService
      .createTextOutput(JSON.stringify({ 
        success: false, 
        error: error.toString() 
      }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

// Test function to verify the script works
function testAppendRow() {
  const testData = {
    action: 'appendRow',
    spreadsheetId: 'YOUR_SPREADSHEET_ID',
    sheetName: 'Sheet1',
    data: ['Test Entry', 'Value 1', 'Value 2'],
    timestamp: new Date().toISOString(),
    userId: 'test-user'
  };
  
  const response = doPost({
    postData: {
      contents: JSON.stringify(testData)
    }
  });
  
  console.log(response.getContent());
}
