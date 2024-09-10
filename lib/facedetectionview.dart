
import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:facesdk_plugin/facedetection_interface.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:facesdk_plugin/facesdk_plugin.dart';
import 'main.dart';
import 'person.dart';

// ignore: must_be_immutable
class FaceRecognitionView extends StatefulWidget {
  final List<Person> personList;
  FaceDetectionViewController? faceDetectionViewController;

  FaceRecognitionView({super.key, required this.personList});

  @override
  State<StatefulWidget> createState() => FaceRecognitionViewState();
}

class FaceRecognitionViewState extends State<FaceRecognitionView> {
  dynamic _faces;
  double _livenessThreshold = 0;
  double _identifyThreshold = 0;
  bool _recognized = false;
  String _identifiedName = "";
  String _identifiedSimilarity = "";
  String _identifiedLiveness = "";
  String _identifiedYaw = "";
  String _identifiedRoll = "";
  String _identifiedPitch = "";
  // ignore: prefer_typing_uninitialized_variables
  var _identifiedFace;
  // ignore: prefer_typing_uninitialized_variables
  var _enrolledFace;
  final _facesdkPlugin = FacesdkPlugin();
  FaceDetectionViewController? faceDetectionViewController;

  @override
  void initState() {
    super.initState();

    loadSettings();
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    String? livenessThreshold = prefs.getString("liveness_threshold");
    String? identifyThreshold = prefs.getString("identify_threshold");
    setState(() {
      _livenessThreshold = double.parse(livenessThreshold ?? "0.7");
      _identifyThreshold = double.parse(identifyThreshold ?? "0.8");
    });
  }

  Future<void> faceRecognitionStart() async {
    final prefs = await SharedPreferences.getInstance();
    var cameraLens = prefs.getInt("camera_lens");

    setState(() {
      _faces = null;
      _recognized = false;
    });

    await faceDetectionViewController?.startCamera(cameraLens ?? 1);
  }

  Future<Position> getUserLocation() async {
    // Request permission at runtime
    var status = await Permission.location.request();
    if (status.isGranted) {
      // Location permission granted, get the current position
      return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } else if (status.isDenied) {
      // Location permission denied, handle accordingly
      throw Exception("Location permission denied");
    } else if (status.isPermanentlyDenied) {
      // Open app settings if permission is permanently denied
      openAppSettings();
    }

    return Future.error("Location permissions are not granted");
  }
  void onUserFaceIdentified(Position userPosition, String companyId) async {
    IdentificationService identificationService = IdentificationService();
    bool isValid = await identificationService.isUserAtCompanyLocation(userPosition, companyId);

    if (isValid) {
      // Retrieve company start time
      DocumentSnapshot companySnapshot = await FirebaseFirestore.instance.collection('companies').doc(companyId).get();
      if (companySnapshot.exists) {
        String companyStartTimeStr = companySnapshot['startTime']; // Should be "04:00"

        // Parse the start time from Firebase (we assume this is in "HH:mm" format)
        DateTime now = DateTime.now();
        DateTime companyStartTime = DateTime(
            now.year,
            now.month,
            now.day,
            int.parse(companyStartTimeStr.split(":")[0]), // hour
            int.parse(companyStartTimeStr.split(":")[1])  // minute
        );

        // Get the current time
        DateTime currentTime = DateTime.now();

        // Calculate late time in minutes
        Duration lateDuration = currentTime.difference(companyStartTime);
        int lateMinutes = lateDuration.inMinutes > 0 ? lateDuration.inMinutes : 0; // if not late, set to 0

        // Format the day_month_year variable
        String dayMonthYear = '${now.day}-${now.month}-${now.year}';

        // Save identification and late time in Firebase
        await FirebaseFirestore.instance.collection('identifications').add({
          'name': 'user_id_here',
          'companyId': companyId,
          'time': currentTime.toString(),
          'lateTime': lateMinutes,
          'day_month_year': dayMonthYear,
        });

        print('Identification successful and recorded. Late time: $lateMinutes minutes');
      } else {
        print('Company not found.');
      }
    } else {
      print('Identification failed due to invalid time or location.');
    }
  }


  Future<bool> onFaceDetected(faces) async {
    if (_recognized) {
      return false;
    }

    if (!mounted) return false;

    setState(() {
      _faces = faces;
    });

    bool recognized = false;
    double maxSimilarity = -1;
    String maxSimilarityName = "";
    double maxLiveness = -1;
    if (faces.isNotEmpty) {
      var face = faces[0];
      for (var person in widget.personList) {
        double similarity = await _facesdkPlugin.similarityCalculation(
            face['templates'], person.templates) ??
            -1;
        if (maxSimilarity < similarity) {
          maxSimilarity = similarity;
          maxSimilarityName = person.name;
          maxLiveness = face['liveness'];
        }
      }

      if (maxSimilarity > _identifyThreshold && maxLiveness > _livenessThreshold) {
        recognized = true;

        // Save to Firestore
        final timestamp = DateTime.now().toIso8601String();
        Position position =await getUserLocation();
        onUserFaceIdentified(position,'holla');
        // FirebaseFirestore.instance.collection('identifications').add({
        //   'name': maxSimilarityName,
        //   'time': timestamp,
        // });
      }
    }



    setState(() {
      _recognized = recognized;
    });

    return recognized;
  }


  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        faceDetectionViewController?.stopCamera();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Face Recognition'),
          toolbarHeight: 70,
          centerTitle: true,
        ),
        body: Stack(
          children: <Widget>[
            FaceDetectionView(faceRecognitionViewState: this),
            SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: CustomPaint(
                painter: FacePainter(
                    faces: _faces, livenessThreshold: _livenessThreshold),
              ),
            ),
            Visibility(
                visible: _recognized,
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: Theme.of(context).colorScheme.background,
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        const SizedBox(
                          height: 10,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: <Widget>[
                            _enrolledFace != null
                                ? Column(
                              children: [
                                ClipRRect(
                                  borderRadius:
                                  BorderRadius.circular(8.0),
                                  child: Image.memory(
                                    _enrolledFace,
                                    width: 160,
                                    height: 160,
                                  ),
                                ),
                                const SizedBox(
                                  height: 5,
                                ),
                                const Text('Enrolled')
                              ],
                            )
                                : const SizedBox(
                              height: 1,
                            ),
                            _identifiedFace != null
                                ? Column(
                              children: [
                                ClipRRect(
                                  borderRadius:
                                  BorderRadius.circular(8.0),
                                  child: Image.memory(
                                    _identifiedFace,
                                    width: 160,
                                    height: 160,
                                  ),
                                ),
                                const SizedBox(
                                  height: 5,
                                ),
                                const Text('Identified')
                              ],
                            )
                                : const SizedBox(
                              height: 1,
                            )
                          ],
                        ),
                        const SizedBox(
                          height: 10,
                        ),
                        Row(
                          children: [
                            const SizedBox(
                              width: 16,
                            ),
                            Text(
                              'Identified: $_identifiedName',
                              style: const TextStyle(fontSize: 18),
                            )
                          ],
                        ),
                        const SizedBox(
                          height: 10,
                        ),
                        Row(
                          children: [
                            const SizedBox(
                              width: 16,
                            ),
                            Text(
                              'Similarity: $_identifiedSimilarity',
                              style: const TextStyle(fontSize: 18),
                            )
                          ],
                        ),
                        const SizedBox(
                          height: 10,
                        ),
                        Row(
                          children: [
                            const SizedBox(
                              width: 16,
                            ),
                            Text(
                              'Liveness score: $_identifiedLiveness',
                              style: const TextStyle(fontSize: 18),
                            )
                          ],
                        ),
                        const SizedBox(
                          height: 10,
                        ),
                        Row(
                          children: [
                            const SizedBox(
                              width: 16,
                            ),
                            Text(
                              'Yaw: $_identifiedYaw',
                              style: const TextStyle(fontSize: 18),
                            )
                          ],
                        ),
                        const SizedBox(
                          height: 10,
                        ),
                        Row(
                          children: [
                            const SizedBox(
                              width: 16,
                            ),
                            Text(
                              'Roll: $_identifiedRoll',
                              style: const TextStyle(fontSize: 18),
                            )
                          ],
                        ),
                        const SizedBox(
                          height: 10,
                        ),
                        Row(
                          children: [
                            const SizedBox(
                              width: 16,
                            ),
                            Text(
                              'Pitch: $_identifiedPitch',
                              style: const TextStyle(fontSize: 18),
                            )
                          ],
                        ),
                        const SizedBox(
                          height: 16,
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                          ),
                          onPressed: () => faceRecognitionStart(),
                          child: const Text('Try again'),
                        ),
                      ]),
                )),
          ],
        ),
      ),
    );
  }
}

class FaceDetectionView extends StatefulWidget
    implements FaceDetectionInterface {
  FaceRecognitionViewState faceRecognitionViewState;

  FaceDetectionView({super.key, required this.faceRecognitionViewState});

  @override
  Future<void> onFaceDetected(faces) async {
    await faceRecognitionViewState.onFaceDetected(faces);
  }

  @override
  State<StatefulWidget> createState() => _FaceDetectionViewState();
}

class _FaceDetectionViewState extends State<FaceDetectionView> {
  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidView(
        viewType: 'facedetectionview',
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    } else {
      return UiKitView(
        viewType: 'facedetectionview',
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    }
  }

  void _onPlatformViewCreated(int id) async {
    final prefs = await SharedPreferences.getInstance();
    var cameraLens = prefs.getInt("camera_lens");

    widget.faceRecognitionViewState.faceDetectionViewController =
        FaceDetectionViewController(id, widget);

    await widget.faceRecognitionViewState.faceDetectionViewController
        ?.initHandler();

    int? livenessLevel = prefs.getInt("liveness_level");
    await widget.faceRecognitionViewState._facesdkPlugin
        .setParam({'check_liveness_level': livenessLevel ?? 0});

    await widget.faceRecognitionViewState.faceDetectionViewController
        ?.startCamera(cameraLens ?? 1);
  }
}

class FacePainter extends CustomPainter {
  dynamic faces;
  double livenessThreshold;
  FacePainter({required this.faces, required this.livenessThreshold});

  @override
  void paint(Canvas canvas, Size size) {
    if (faces != null) {
      var paint = Paint();
      paint.color = const Color.fromARGB(0xff, 0xff, 0, 0);
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 3;

      for (var face in faces) {
        double xScale = face['frameWidth'] / size.width;
        double yScale = face['frameHeight'] / size.height;

        String title = "";
        Color color = const Color.fromARGB(0xff, 0xff, 0, 0);
        if (face['liveness'] < livenessThreshold) {
          color = const Color.fromARGB(0xff, 0xff, 0, 0);
          title = "Spoof" + face['liveness'].toString();
        } else {
          color = const Color.fromARGB(0xff, 0, 0xff, 0);
          title = "Real " + face['liveness'].toString();
        }

        TextSpan span =
        TextSpan(style: TextStyle(color: color, fontSize: 20), text: title);
        TextPainter tp = TextPainter(
            text: span,
            textAlign: TextAlign.left,
            );
        tp.layout();
        tp.paint(canvas, Offset(face['x1'] / xScale, face['y1'] / yScale - 30));

        paint.color = color;
        canvas.drawRect(
            Offset(face['x1'] / xScale, face['y1'] / yScale) &
            Size((face['x2'] - face['x1']) / xScale,
                (face['y2'] - face['y1']) / yScale),
            paint);
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
