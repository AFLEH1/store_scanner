import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

void main() {
  runApp(const StoreApp());
}

class StoreApp extends StatelessWidget {
  const StoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'عدسة المتجر',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Database? _db;
  Interpreter? _interpreter;
  String _resultText = "النتيجة ستظهر هنا";

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'store.db'),
      version: 1,
      onCreate: (db, version) {
        return db.execute('''
          CREATE TABLE products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            price REAL NOT NULL,
            barcode TEXT UNIQUE,
            embedding BLOB
          )
        ''');
      },
    );

    try {
      _interpreter = await Interpreter.fromAsset('assets/mobilenet.tflite');
    } catch (e) {
      setState(() {
        _resultText = "خطأ في تحميل نموذج الذكاء الاصطناعي: $e";
      });
    }
  }

  List<double> _getEmbedding(File imageFile) {
    final rawBytes = imageFile.readAsBytesSync();
    final decodedImage = img.decodeImage(rawBytes)!;
    final resized = img.copyResize(decodedImage, width: 224, height: 224);

    var input = List.generate(
      1,
      (i) => List.generate(
        224,
        (y) => List.generate(
          224,
          (x) {
            final pixel = resized.getPixel(x, y);
            return [
              pixel.r / 255.0,
              pixel.g / 255.0,
              pixel.b / 255.0,
            ];
          },
        ),
      ),
    );

    var output = List.filled(1 * 1001, 0.0).reshape([1, 1001]);
    _interpreter!.run(input, output);
    return List<double>.from(output[0]);
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  Future<void> _searchByImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile == null) return;

    setState(() => _resultText = "جاري التحليل والبحث...");

    final file = File(pickedFile.path);
    final queryVector = _getEmbedding(file);

    final List<Map<String, dynamic>> rows = await _db!.query(
      'products',
      where: 'embedding IS NOT NULL',
    );

    String? bestName;
    double? bestPrice;
    double highestScore = -1.0;

    for (var row in rows) {
      final Float32List blobBytes = Float32List.sublistView(Uint8List.fromList(row['embedding']));
      final dbVector = blobBytes.toList();
      final score = _cosineSimilarity(queryVector, dbVector);

      if (score > highestScore) {
        highestScore = score;
        bestName = row['name'];
        bestPrice = row['price'];
      }
    }

    if (highestScore > 0.40 && bestName != null) {
      setState(() {
        _resultText = "✅ المنتج: $bestName\n💰 السعر: $bestPrice\n🔍 مطابقة بصرية: ${(highestScore * 100).toInt()}%";
      });
    } else {
      setState(() {
        _resultText = "❌ لم يتم العثور على منتج مطابق.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('عدسة المتجر (Offline APK)')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: _searchByImage,
              icon: const Icon(Icons.camera_alt),
              label: const Text('بحث عن منتج بالصورة'),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[200],
              child: Text(
                _resultText,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
