class TradeQRScannerPage extends StatefulWidget {
  final String tierName;
  final int coreCount;
  final Character fromCharacter;

  const TradeQRScannerPage({
    Key? key,
    required this.tierName,
    required this.coreCount,
    required this.fromCharacter,
  }) : super(key: key);

  @override
  _TradeQRScannerPageState createState() => _TradeQRScannerPageState();
}

class _TradeQRScannerPageState extends State<TradeQRScannerPage> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  bool isScanning = true;
  String? scannedData;

  @override
  void initState() {
    super.initState();
    print('TradeQRScannerPage initialized');
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void _onQRViewCreated(QRViewController controller) {
    print('QR View created successfully');
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      print('QR Scanner detected data: ${scanData.code}');
      if (scanData.code != null && scanData.code!.isNotEmpty) {
        print('Processing QR code: ${scanData.code}');
        _handleQRCodeScan(scanData.code!);
      }
    });
  }

  void _handleQRCodeScan(String code) {
    if (!isScanning) return; // Prevent multiple scans
    
    // Prevent processing the same QR code multiple times
    if (scannedData == code) return;
    
    setState(() {
      isScanning = false;
      scannedData = code;
    });
    
    // Stop the camera immediately after scan
    controller?.pauseCamera();
    
    _processScannedData(code);
  }

  void _processScannedData(String data) {
    try {
      // Check if the data looks like JSON
      if (!data.trim().startsWith('{') || !data.trim().endsWith('}')) {
        if (mounted) {
          _showError('This doesn\'t appear to be a valid player QR code. Please scan a player QR code.');
        }
        return;
      }

      // Parse the QR code data
      final Map<String, dynamic> playerData = json.decode(data);
      
      // Validate the QR code format
      if (playerData.containsKey('game') && playerData['game'] == 'Crucible' && playerData.containsKey('playerUid')) {
        // Profile QR code format - return the data
        Navigator.of(context).pop(playerData);
        return;
      }
      
      if (playerData.containsKey('uid') && playerData.containsKey('characters')) {
        // Old format with direct character data - return the data
        Navigator.of(context).pop(playerData);
        return;
      }
      
      if (mounted) {
        _showError('This QR code is not a valid player profile. Please scan a player QR code from the Profile page.');
      }
    } catch (e) {
      print('QR Code parsing error: $e');
      if (mounted) {
        _showError('Invalid QR code format. Please scan a valid player QR code.\n\nError: ${e.toString()}');
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error, color: Colors.red),
              SizedBox(width: 8),
              Text('Scan Error'),
            ],
          ),
          content: Text(message),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _resetScanner();
              },
              child: Text('Try Again'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(); // Go back to character sheet
              },
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _resetScanner() {
    print('Resetting QR scanner...');
    setState(() {
      isScanning = true;
      scannedData = null;
    });
    // Restart the camera if needed
    controller?.resumeCamera();
    print('QR scanner reset complete');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Trade ${widget.tierName} Core'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: QRView(
              key: qrKey,
              onQRViewCreated: _onQRViewCreated,
              overlay: QrScannerOverlayShape(
                borderColor: Colors.blue,
                borderRadius: 10,
                borderLength: 30,
                borderWidth: 10,
                cutOutSize: 300,
              ),
            ),
          ),
          Container(
            height: 120,
            padding: EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.qr_code_scanner,
                  size: 32,
                  color: Colors.blue,
                ),
                SizedBox(height: 8),
                Text(
                  'Scan player QR code',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                if (scannedData != null) ...[
                  SizedBox(height: 4),
                  Text(
                    'Processing...',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ] else if (isScanning) ...[
                  SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _resetScanner,
                    icon: Icon(Icons.refresh, size: 16),
                    label: Text('Reset Scanner', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
