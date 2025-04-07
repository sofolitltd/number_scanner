import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  runApp(CameraTextScannerApp(camera: firstCamera));
}

class CameraTextScannerApp extends StatelessWidget {
  final CameraDescription camera;

  const CameraTextScannerApp({super.key, required this.camera});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: CameraScreen(camera: camera),
    );
  }
}

class CameraScreen extends StatefulWidget {
  final CameraDescription camera;

  const CameraScreen({super.key, required this.camera});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  final TextEditingController _scannedTextController = TextEditingController();
  File? _capturedImage;
  File? _croppedFile;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.camera, ResolutionPreset.high);
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scannedTextController.dispose();
    super.dispose();
  }

  //
  Future<void> _performOCR(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final textRecognizer = TextRecognizer();
      final recognizedText = await textRecognizer.processImage(inputImage);

      String scannedText = '';
      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          scannedText += line.text;
        }
      }

      scannedText = scannedText.replaceAll(' ', '');
      setState(() {
        _scannedTextController.text = scannedText.trim();
      });

      await textRecognizer.close();
    } catch (e) {
      print('OCR Error: $e');
    }
  }

  //
  Future<void> _scanText() async {
    setState(() {
      _capturedImage = null;
      _croppedFile = null;
    });

    try {
      await _initializeControllerFuture;
      final image = await _controller.takePicture();
      final imageBytes = File(image.path).readAsBytesSync();
      final uiImage = await decodeImageFromList(imageBytes);

      final RenderBox renderBox = context.findRenderObject() as RenderBox;

      final topLeft = renderBox.localToGlobal(
        Offset(renderBox.size.width / 2 - 150, 80),
      );
      final bottomRight = renderBox.localToGlobal(
        Offset(renderBox.size.width / 2 + 150, 80 + 48),
      );

      final scaleX = uiImage.width / renderBox.size.width;
      final scaleY = uiImage.height / renderBox.size.height;
      final cropRect = Rect.fromLTRB(
        topLeft.dx * scaleX,
        topLeft.dy * scaleY,
        bottomRight.dx * scaleX,
        bottomRight.dy * scaleY,
      );

      final decodedImage = img.decodeImage(imageBytes)!;
      final croppedImage = img.copyCrop(
        decodedImage,
        x: cropRect.left.toInt(),
        y: cropRect.top.toInt(),
        width: cropRect.width.toInt(),
        height: cropRect.height.toInt(),
      );

      _croppedFile = File(
        '${(await getTemporaryDirectory()).path}/${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await _croppedFile!.writeAsBytes(img.encodePng(croppedImage));

      setState(() {
        _capturedImage = _croppedFile;
      });

      await _performOCR(_croppedFile!);
    } catch (e) {
      print('Camera scan error: $e');
    }
  }

  //
  Future<void> _pickImageFromGallery() async {
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (pickedFile != null) {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Image',
            toolbarColor: Colors.red,
            toolbarWidgetColor: Colors.white,
            lockAspectRatio: false,
            hideBottomControls: true,
            showCropGrid: false,
            cropFrameStrokeWidth: 1,
          ),
        ],
      );

      if (croppedFile != null) {
        final file = File(croppedFile.path);
        setState(() {
          _capturedImage = file;
          _croppedFile = file;
        });

        await _performOCR(file);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Number Scanner'),
        centerTitle: true,
        backgroundColor: Colors.red,
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            // Define the rectangle area
            final rect = Rect.fromCenter(
              center: Offset(MediaQuery.of(context).size.width / 2, 80),
              width: 300,
              height: 64,
            );

            return Stack(
              children: [
                //01704340860
                CameraPreview(_controller),

                //
                CustomPaint(size: Size.infinite, painter: OverlayPainter(rect)),

                //create a btn to upload image from gallery
                Positioned(
                  top: 120,
                  right: 16,
                  left: 16,
                  child: Column(
                    spacing: 10,
                    children: [
                      Text('or'),

                      //
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size(300, 56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(0),
                          ),
                        ),
                        onPressed: _pickImageFromGallery,
                        icon: Icon(Icons.photo_library, color: Colors.white),
                        label: Text(
                          'Upload from Gallery',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            letterSpacing: 1,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                //
                Positioned(
                  bottom: 260,
                  right: 16,
                  left: 16,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      minimumSize: Size(MediaQuery.sizeOf(context).width, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                    onPressed: _scanText,
                    child: Text(
                      'Scan Number',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        letterSpacing: 1,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                //
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    width: MediaQuery.of(context).size.width,
                    padding: const EdgeInsets.symmetric(
                      vertical: 24,
                      horizontal: 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      spacing: 16,
                      children: [
                        // if (_capturedImage != null)
                        Column(
                          children: [
                            //
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                //
                                Container(
                                  height: 56,
                                  decoration:
                                      _capturedImage == null
                                          ? BoxDecoration(
                                            border: Border.all(
                                              color: Colors.black12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          )
                                          : BoxDecoration(
                                            border: Border.all(
                                              color: Colors.black12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            image: DecorationImage(
                                              image: FileImage(_capturedImage!),
                                            ),
                                          ),
                                  child:
                                      _capturedImage == null
                                          ? Center(
                                            child: Text('No image capture!'),
                                          )
                                          : null,
                                ),

                                //
                                if (_capturedImage != null)
                                  Positioned(
                                    top: -8,
                                    right: -8,
                                    child: IconButton.filled(
                                      visualDensity: VisualDensity(
                                        vertical: -2,
                                        horizontal: -4,
                                      ),
                                      onPressed: () {
                                        // clean image
                                        setState(() {
                                          _capturedImage = null;
                                          _scannedTextController.clear();
                                        });
                                      },
                                      icon: Icon(Icons.close, size: 16),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),

                        //
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.black45),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Row(
                            children: [
                              //
                              Expanded(
                                child: TextFormField(
                                  controller: _scannedTextController,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.all(8),
                                  ),
                                ),
                              ),

                              const SizedBox(width: 8),

                              //
                              MaterialButton(
                                color: Colors.redAccent,
                                height: 48,
                                // minWidth: 40,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                onPressed: () {
                                  String text =
                                      _scannedTextController.text.trim();

                                  //
                                  if (text.isNotEmpty) {
                                    Clipboard.setData(
                                      ClipboardData(text: text),
                                    ).then((_) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text(text)),
                                      );
                                    });
                                  }
                                },
                                child: const Text('Copy'),
                              ),
                            ],
                          ),
                        ),

                        //
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            //
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _scannedTextController,
                              builder: (context, value, child) {
                                return Align(
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Length: ${value.text.length}',
                                    // Use value.text.length
                                    style: TextStyle(color: Colors.black),
                                  ),
                                );
                              },
                            ),

                            //
                            GestureDetector(
                              onTap: () {
                                //clear text field
                                _scannedTextController.clear();
                              },
                              child: Text(
                                'Clear',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}

//
class OverlayPainter extends CustomPainter {
  final Rect rect;

  OverlayPainter(this.rect);

  @override
  void paint(Canvas canvas, Size size) {
    // Dark overlay
    final paint = Paint()..color = Colors.black87;
    final path =
        Path()
          ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
          ..addRect(rect)
          ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    // White border around the transparent rect
    final borderPaint =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = .1;

    canvas.drawRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
