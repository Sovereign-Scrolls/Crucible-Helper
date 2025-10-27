// Test Google Sheets integration
const { google } = require('googleapis');
const config = require('./config.json');

async function testGoogleSheets() {
  try {
    console.log('🧪 Testing Google Sheets integration...');
    
    // Initialize Google Sheets API
    const auth = new google.auth.GoogleAuth({
      scopes: ['https://www.googleapis.com/auth/spreadsheets'],
      keyFile: './service-account-key.json'
    });
    
    const sheets = google.sheets({ version: 'v4', auth });
    
    // Extract spreadsheet ID from config
    console.log('📊 Raw config:', config.google_sheets.pc_db_spreadsheet_id);
    const rawId = config.google_sheets.pc_db_spreadsheet_id;
    // Handle different URL formats
    let spreadsheetId;
    if (rawId.includes('/d/')) {
      // Format: https://docs.google.com/spreadsheets/d/ID/edit?gid=...
      spreadsheetId = rawId.split('/d/')[1].split('/')[0];
    } else if (rawId.includes('/')) {
      // Format: ID/edit?gid=...
      spreadsheetId = rawId.split('/')[0].split('?')[0];
    } else {
      // Already just the ID
      spreadsheetId = rawId.split('?')[0];
    }
    console.log('📊 Extracted Spreadsheet ID:', spreadsheetId);
    
    // Test reading the spreadsheet
    console.log('📖 Testing spreadsheet access...');
    const response = await sheets.spreadsheets.get({
      spreadsheetId: spreadsheetId
    });
    
    console.log('✅ Spreadsheet access successful!');
    console.log('📋 Sheet titles:', response.data.sheets.map(s => s.properties.title));
    
    // Check if "Form Responses" sheet exists
    const formResponsesSheet = response.data.sheets.find(s => 
      s.properties.title.toLowerCase().includes('form responses')
    );
    
    if (formResponsesSheet) {
      console.log('✅ "Form Responses" sheet found!');
      
      // Test writing to the sheet
      console.log('✍️ Testing write access...');
      const testData = [
        new Date().toISOString(),
        'test@example.com',
        'Test Character',
        'Test Player',
        'Human',
        'Attack'
      ];
      
      const writeResponse = await sheets.spreadsheets.values.append({
        spreadsheetId: spreadsheetId,
        range: 'Form Responses!A:F',
        valueInputOption: 'RAW',
        insertDataOption: 'INSERT_ROWS',
        resource: {
          values: [testData]
        }
      });
      
      console.log('✅ Write test successful!');
      console.log('📊 Response:', writeResponse.data);
      
    } else {
      console.log('❌ "Form Responses" sheet not found!');
      console.log('📋 Available sheets:', response.data.sheets.map(s => s.properties.title));
    }
    
  } catch (error) {
    console.error('❌ Error testing Google Sheets:', error.message);
    if (error.response) {
      console.error('📊 Error details:', error.response.data);
    }
  }
}

testGoogleSheets();
