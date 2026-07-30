# Notebook App — Flutter

A tablet-first handwriting notebook app built with Flutter. No backend required — notes are saved locally using `shared_preferences`.

## Features
- Create and manage multiple notes
- Freehand handwriting with Apple Pencil / stylus / finger
- 8 pen colours
- 4 stroke widths
- Eraser tool
- Undo last stroke
- Ruled notebook line background
- Notes saved locally on device
- Thumbnail preview on home screen
- Responsive: tablet (3-column grid) and phone (2-column grid)

## Project structure
```
lib/
├── main.dart                  # App entry point
├── models/
│   └── note.dart              # Note & DrawnPoint data models
├── services/
│   └── notes_service.dart     # Save/load notes from SharedPreferences
├── screens/
│   ├── home_screen.dart       # Note list / grid screen
│   └── canvas_screen.dart     # Writing canvas screen
└── widgets/
    ├── drawing_canvas.dart    # GestureDetector + CustomPainter canvas
    └── toolbar_widget.dart    # Pen colour, size, eraser toolbar
```

## Setup

### 1. Install Flutter
https://docs.flutter.dev/get-started/install

### 2. Clone / copy this project

### 3. Install dependencies
```bash
flutter pub get
```

### 4. Run on iPad simulator or device
```bash
# List available devices
flutter devices

# Run on iPad simulator
flutter run -d "iPad"

# Run on connected iPad
flutter run -d <device-id>
```

### 5. Build for iPad (release)
```bash
flutter build ios --release
```
Open `ios/Runner.xcworkspace` in Xcode, set your team, then archive and deploy.

## What to add next (for your FYP)
1. **PDF import** — use `pdfx` or `syncfusion_flutter_pdf` package
2. **AI Chatbot panel** — call Gemini API or OpenAI API
3. **Firebase** — replace `shared_preferences` with Firestore for cloud sync
4. **Community chat** — Firebase Realtime Database + Firebase Storage for file sharing
5. **Apple Pencil pressure** — use `Listener` widget with `PointerEvent.pressure` instead of `GestureDetector`

## Apple Pencil tip
To get pressure sensitivity with Apple Pencil, replace `GestureDetector` in `drawing_canvas.dart` with:
```dart
Listener(
  onPointerDown: (e) => _addPoint(e.localPosition, e.pressure),
  onPointerMove: (e) => _addPoint(e.localPosition, e.pressure),
  onPointerUp: (_) => _liftPen(),
)
```
Then multiply `strokeWidth * pressure` when adding each point.
