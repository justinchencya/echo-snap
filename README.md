# EchoSnap 📸

A sophisticated iOS camera app built with SwiftUI that allows you to take photos while referencing existing images. Perfect for photographers, designers, and anyone who needs to maintain consistency across multiple shots.

## ✨ Features

### 📱 Dual-View Interface
- **Reference Image Panel**: Display and interact with existing photos
- **Camera Panel**: Live camera preview with advanced controls
- **Responsive Layout**: Automatically adapts between portrait and landscape orientations

### 🎯 Advanced Camera Controls
- **Pinch to Zoom**: Adjust zoom factor with intuitive pinch gestures
- **Tap to Focus**: Tap anywhere on the preview to set focus point
- **Long Press for Focus Lock**: Lock focus and exposure for consistent shots
- **Double Tap**: Quick reset of camera settings
- **Manual Exposure Control**: Fine-tune exposure bias for perfect lighting

### 🖼️ Image Management
- **Photo Library Integration**: Select reference images from your device
- **Zoomable Reference Images**: Pinch and pan to examine details
- **Image Transformations**: Reset and manipulate reference images as needed
- **High-Quality Capture**: Optimized for maximum photo quality

### 🎨 Modern UI/UX
- **Beautiful Gradient Design**: Custom color scheme with smooth transitions
- **Card-Based Layout**: Clean, organized interface with rounded corners
- **Smooth Animations**: Spring-based transitions and state changes
- **Responsive Design**: Adapts to different screen sizes and orientations

## 🚀 Getting Started

### Prerequisites
- iOS 15.0 or later
- Xcode 14.0 or later
- iPhone or iPad device for testing

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/EchoSnap.git
   cd EchoSnap
   ```

2. **Open in Xcode**
   - Open `EchoSnap.xcodeproj` in Xcode
   - Select your target device or simulator
   - Build and run the project

3. **Camera Permissions**
   - The app will request camera access on first launch
   - Grant permission to enable camera functionality

## 🏗️ Architecture

### Core Components
- **ContentView**: Main app interface and layout management
- **CameraModel**: Camera session management and photo capture
- **CameraPreview**: SwiftUI wrapper for AVFoundation camera preview
- **Persistence**: Core Data integration for data management

### Key Technologies
- **SwiftUI**: Modern declarative UI framework
- **AVFoundation**: Camera and media capture functionality
- **Core Data**: Data persistence and management
- **PhotosUI**: Photo library integration

## 📱 Usage

### Taking Photos
1. **Select Reference Image**: Tap the placeholder to choose an existing photo
2. **Open Camera**: Tap "Tap to Open Camera" to activate the camera
3. **Adjust Settings**: Use pinch gestures for zoom, tap for focus
4. **Capture**: Tap the capture button to take a photo
5. **Review**: View your captured photo with options to retake or save

### Camera Controls
- **Pinch**: Zoom in/out on the camera preview
- **Single Tap**: Set focus point
- **Double Tap**: Reset camera settings
- **Long Press**: Lock focus and exposure

## 🔧 Development

### Project Structure
```
EchoSnap/
├── EchoSnap/
│   ├── ContentView.swift          # Main app interface
│   ├── EchoSnapApp.swift          # App entry point
│   ├── Persistence.swift          # Core Data setup
│   ├── Assets.xcassets/           # App icons and images
│   └── EchoSnap.xcdatamodeld/    # Data model
├── EchoSnapTests/                 # Unit tests
├── EchoSnapUITests/               # UI tests
└── EchoSnap.xcodeproj/            # Xcode project file
```

### Key Features Implementation
- **Camera Session Management**: Handles camera permissions, session lifecycle, and photo capture
- **Gesture Recognition**: Implements pinch, tap, and long press gestures for camera control
- **Orientation Handling**: Responsive layout that adapts to device orientation changes
- **Image Processing**: High-quality photo capture with configurable settings

## 🧪 Testing

### Running Tests
1. Open the project in Xcode
2. Select Product → Test (⌘+U)
3. View test results in the Test navigator

### Test Coverage
- **Unit Tests**: Core functionality and business logic
- **UI Tests**: User interface and interaction flows

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 👨‍💻 Author

**Justin Chen**
- Created on December 27, 2024
- Built with SwiftUI and modern iOS development practices

## 🙏 Acknowledgments

- Apple for SwiftUI and AVFoundation frameworks
- The iOS development community for inspiration and best practices
- Users and testers for valuable feedback

---

**EchoSnap** - Capture memories with precision and style 📸✨
