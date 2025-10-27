// ===== QR: signing secret =====

function getSigningSecret_() {
  const s = PropertiesService.getScriptProperties().getProperty('QR_SIGNING_SECRET');
  if (!s) throw new Error('Missing QR_SIGNING_SECRET. Run setSigningSecret_("...") once.');
  return s;
}

// ===== QR: main one-call helper =====
// Generates QR from the pc JSON object and uploads it to users/{playerEmail}/qr.png
// Returns { qrUrl, qrText, sig, issuedAt, rev, qrPath }
function generateAndUploadQrForPc_(pc) {
  // Required fields
  if (!pc || !pc.playerEmail || !pc.playerName || !pc.characterName || pc.characterNumber == null) {
    throw new Error('QR: pc missing playerEmail, playerName, characterName, or characterNumber');
  }

  // Compute revision from the JSON we’re actually uploading
  const pcJson = JSON.stringify(pc);
  const rev = sha256Hex_(pcJson).slice(0, 10);

  // Canonical string and signature
  const issuedAt = new Date().toISOString();
  const canonical = [
    'v1',
    String(pc.characterNumber).trim(),
    pc.playerName.trim(),
    pc.characterName.trim(),
    rev,
    issuedAt
  ].join('|');
  const sig = hmac256Hex_(canonical, getSigningSecret_()).slice(0, 16);

  // Compact payload text
  const qrObj = {
    v: 1,
    cid: String(pc.characterNumber).trim(),
    pn: pc.playerName.trim(),
    cn: pc.characterName.trim(),
    rev,
    iat: issuedAt,
    sig
  };
  const qrText = 'ss://pc?' + toQuery_(qrObj);

  // Render QR png and upload next to pc.json
  const qrPng = generateQrPng_(qrText, 512);
  const qrPath = `users/${pc.playerEmail}/qr.png`; // same folder as users/${email}/pc.json
  const qrUrl  = uploadBlobToStorage_(qrPath, qrPng);

  return { qrUrl, qrText, sig, issuedAt, rev, qrPath };
}


function generateQrPng_(text, size) {
  // Build query with encoding for *all* values, including 'M|0'
  const params = {
    cht: 'qr',
    chs: `${size}x${size}`,
    choe: 'UTF-8',
    chld: 'M|0',          // will be encoded to M%7C0
    chl: text             // full payload; we encode below as a value
  };

  const googleUrl =
    'https://chart.googleapis.com/chart?' +
    Object.keys(params)
      .map(k => k + '=' + encodeURIComponent(params[k]))
      .join('&');

  // Try Google Image Charts first
  let resp = UrlFetchApp.fetch(googleUrl, { muteHttpExceptions: true });
  let code = resp.getResponseCode();
  if (code === 200) {
    return resp.getBlob().setName('qr.png').setContentType('image/png');
  }

  // Fallback: QuickChart (compatible and fast)
  const quickUrl =
    'https://quickchart.io/qr?text=' + encodeURIComponent(text) +
    '&size=' + encodeURIComponent(String(size));

  resp = UrlFetchApp.fetch(quickUrl, { muteHttpExceptions: true });
  code = resp.getResponseCode();
  if (code === 200) {
    return resp.getBlob().setName('qr.png').setContentType('image/png');
  }

  throw new Error(
    'QR generation failed – Google(' + googleUrl + ' → ' + code + ') ' +
    'and QuickChart(' + quickUrl + ' → ' + resp.getResponseCode() + ')'
  );
}


function toQuery_(obj) {
  return Object.keys(obj)
    .map(k => k + '=' + encodeURIComponent(String(obj[k])))
    .join('&');
}

function hmac256Hex_(data, secret) {
  const bytes = Utilities.computeHmacSha256Signature(data, secret);
  return bytesToHex_(bytes);
}

function sha256Hex_(text) {
  const bytes = Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, text, Utilities.Charset.UTF_8);
  return bytesToHex_(bytes);
}

function bytesToHex_(bytes) {
  return bytes.map(b => ('0' + (b & 0xff).toString(16)).slice(-2)).join('');
}

// ===== Generic blob uploader that uses Script Property STORAGE_BUCKET =====
function uploadBlobToStorage_(objectPath, blob) {
  const bucket = getStorageBucket_();        // <-- you already added this
  const token  = ScriptApp.getOAuthToken();

  const url = `https://storage.googleapis.com/upload/storage/v1/b/${encodeURIComponent(bucket)}/o` +
              `?uploadType=media&name=${encodeURIComponent(objectPath)}`;

  const res = UrlFetchApp.fetch(url, {
    method: 'post',
    contentType: blob.getContentType(),
    payload: blob.getBytes(),
    headers: { Authorization: 'Bearer ' + token },
    muteHttpExceptions: true
  });

  const code = res.getResponseCode();
  const body = res.getContentText();
  if (code !== 200 && code !== 201) {
    throw new Error('GCS upload failed: ' + code + ' – ' + body);
  }

  const meta = JSON.parse(body);
  return `https://storage.googleapis.com/${encodeURIComponent(bucket)}/${encodeURIComponent(meta.name)}`;
}
