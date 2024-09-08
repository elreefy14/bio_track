import 'dart:math';

import 'package:flutter/material.dart';
import 'package:facesdk_plugin/facesdk_plugin.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_exif_rotation/flutter_exif_rotation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'dart:io' show Platform;
import 'about.dart';
import 'settings.dart';
import 'person.dart';
import 'personview.dart';
import 'facedetectionview.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face and Fingerprint Recognition',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: MyHomePage(title: 'Face & Fingerprint Recognition'),
    );
  }
}

// ignore: must_be_immutable
class MyHomePage extends StatefulWidget {
  final String title;
  var personList = <Person>[];

  MyHomePage({super.key, required this.title});

  @override
  MyHomePageState createState() => MyHomePageState();
}

class MyHomePageState extends State<MyHomePage> {
  String _warningState = "";
  bool _visibleWarning = false;
  final LocalAuthentication auth = LocalAuthentication(); // Add local auth instance
  final _facesdkPlugin = FacesdkPlugin();

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    // Existing Face SDK setup...
    List<Person> personList = await loadAllPersons();
    await SettingsPageState.initSettings();

    final prefs = await SharedPreferences.getInstance();
    int? livenessLevel = prefs.getInt("liveness_level");

    try {
      await _facesdkPlugin
          .setParam({'check_liveness_level': livenessLevel ?? 0});
    } catch (e) {}

    if (!mounted) return;

    setState(() {
      widget.personList = personList;
    });
  }

  Future<Database> createDB() async {
    final database = openDatabase(
      join(await getDatabasesPath(), 'person.db'),
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE person(name text, faceJpg blob, templates blob)',
        );
      },
      version: 1,
    );

    return database;
  }

  Future<List<Person>> loadAllPersons() async {
    final db = await createDB();
    final List<Map<String, dynamic>> maps = await db.query('person');
    return List.generate(maps.length, (i) {
      return Person.fromMap(maps[i]);
    });
  }

  Future<void> insertPerson(Person person) async {
    final db = await createDB();
    await db.insert('person', person.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    setState(() {
      widget.personList.add(person);
    });
  }

  Future enrollPerson() async {
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image == null) return;

      var rotatedImage =
      await FlutterExifRotation.rotateImage(path: image.path);

      final faces = await _facesdkPlugin.extractFaces(rotatedImage.path);
      for (var face in faces) {
        Person person = Person(
            name: 'Person${Random().nextInt(10000)}',
            faceJpg: face['faceJpg'],
            templates: face['templates']);
        insertPerson(person);
      }

      if (faces.isEmpty) {
        Fluttertoast.showToast(
            msg: "No face detected!",
            backgroundColor: Colors.red,
            textColor: Colors.white);
      } else {
        Fluttertoast.showToast(
            msg: "Person enrolled!",
            backgroundColor: Colors.green,
            textColor: Colors.white);
      }
    } catch (e) {
      Fluttertoast.showToast(
          msg: "Error enrolling person!",
          backgroundColor: Colors.red,
          textColor: Colors.white);
    }
  }

  // Fingerprint enrollment using biometric auth (local_auth)
  Future<void> enrollFingerprint() async {
    try {
      bool didAuthenticate = await auth.authenticate(
          localizedReason: 'Please authenticate to enroll fingerprint',
          options: const AuthenticationOptions(
            stickyAuth: true,
          ));

      if (didAuthenticate) {
        Fluttertoast.showToast(
            msg: "Fingerprint Enrolled!",
            backgroundColor: Colors.green,
            textColor: Colors.white);
      } else {
        Fluttertoast.showToast(
            msg: "Fingerprint Enrollment Failed!",
            backgroundColor: Colors.red,
            textColor: Colors.white);
      }
    } catch (e) {
      print({e.toString()});
      Fluttertoast.showToast(
          msg: "Error: ${e.toString()}",
          backgroundColor: Colors.red,
          textColor: Colors.white);
    }
  }

  // Fingerprint identification logic
  Future<void> identifyFingerprint() async {
    try {
      bool didAuthenticate = await auth.authenticate(
          localizedReason: 'Please authenticate to identify fingerprint',
          options: const AuthenticationOptions(
            stickyAuth: true,
          ));

      if (didAuthenticate) {
        Fluttertoast.showToast(
            msg: "Fingerprint Identified!",
            backgroundColor: Colors.blue,
            textColor: Colors.white);
      } else {
        Fluttertoast.showToast(
            msg: "Fingerprint Identification Failed!",
            backgroundColor: Colors.red,
            textColor: Colors.white);
      }
    } catch (e) {
      Fluttertoast.showToast(
          msg: "Error: ${e.toString()}",
          backgroundColor: Colors.red,
          textColor: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Face & Fingerprint Recognition'),
        centerTitle: true,
      ),
      body: Container(
        margin: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: ElevatedButton.icon(
                      label: const Text('Enroll Fingerprint'),
                      icon: const Icon(Icons.fingerprint),
                      onPressed: enrollFingerprint),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: ElevatedButton.icon(
                      label: const Text('Identify Fingerprint'),
                      icon: const Icon(Icons.search),
                      onPressed: identifyFingerprint),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: ElevatedButton.icon(
                      label: const Text('Enroll Face'),
                      icon: const Icon(Icons.person_add),
                      onPressed: enrollPerson),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: ElevatedButton.icon(
                      label: const Text('Identify Face'),
                      icon: const Icon(Icons.person_search),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => FaceRecognitionView(
                                personList: widget.personList,
                              )),
                        );
                      }),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
                child: PersonView(
                  personList: widget.personList,
                  homePageState: this,
                )),
            const SizedBox(height: 4),
            const Text('KBY-AI Technology',
                style: TextStyle(
                  fontSize: 18,
                  color: Color.fromARGB(255, 60, 60, 60),
                )),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
