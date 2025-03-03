//
//  ContentView.swift
//  EchoSnap
//
//  Created by Justin Chen on 12/27/24.
//

import SwiftUI
import CoreData
import AVFoundation
import UIKit

extension Color {
    static let appGradientStart = Color(hex: "4A90E2")
    static let appGradientEnd = Color(hex: "357ABD")
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let videoOrientation: AVCaptureVideoOrientation
    
    class PreviewView: UIView {
        override class var layerClass: AnyClass {
            return AVCaptureVideoPreviewLayer.self
        }
        
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()
            videoPreviewLayer.frame = bounds
        }
    }
    
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspect
        view.videoPreviewLayer.connection?.videoOrientation = videoOrientation
        
        return view
    }
    
    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.connection?.videoOrientation = videoOrientation
    }
}

class CameraModel: NSObject, ObservableObject {
    @Published var session = AVCaptureSession()
    @Published var recentImage: UIImage?
    @Published var isPhotoTaken = false
    @Published var isPreviewActive = false
    @Published var photoCount: Int = UserDefaults.standard.integer(forKey: "photoCount")
    private var isCameraAuthorized = false
    private let output = AVCapturePhotoOutput()
    
    override init() {
        super.init()
        checkPermissions()
    }
    
    private func restartCameraSession() {
        recentImage = nil
        isPhotoTaken = false
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }
    }
    
    func togglePreview() {
        isPreviewActive.toggle()
        if isPreviewActive {
            if !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async {
                    self.session.startRunning()
                }
            }
        } else {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }
    
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        
        // Configure for maximum quality
        settings.photoQualityPrioritization = .quality
        
        // Enable high quality capture
        settings.isHighResolutionPhotoEnabled = true
        
        // Get the video orientation from the interface orientation
        if let connection = output.connection(with: .video) {
            if let interfaceOrientation = UIWindow.key?.windowScene?.interfaceOrientation {
                let videoOrientation: AVCaptureVideoOrientation
                switch interfaceOrientation {
                case .portrait:
                    videoOrientation = .portrait
                case .portraitUpsideDown:
                    videoOrientation = .portraitUpsideDown
                case .landscapeLeft:
                    videoOrientation = .landscapeLeft
                case .landscapeRight:
                    videoOrientation = .landscapeRight
                default:
                    videoOrientation = .portrait
                }
                connection.videoOrientation = videoOrientation
            }
        }
        
        output.capturePhoto(with: settings, delegate: self)
    }
    
    func savePhotoAndReopen() {
        if let image = recentImage {
            UIImageWriteToSavedPhotosAlbum(image, self, #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
            incrementPhotoCount()
        }
        restartCameraSession()
    }
    
    func discardPhotoAndReopen() {
        restartCameraSession()
    }
    
    func incrementPhotoCount() {
        photoCount += 1
        UserDefaults.standard.set(photoCount, forKey: "photoCount")
    }
    
    func resetPhotoCount() {
        photoCount = 0
        UserDefaults.standard.set(photoCount, forKey: "photoCount")
    }
    
    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.isCameraAuthorized = true
            DispatchQueue.global(qos: .userInitiated).async {
                self.setup()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.isCameraAuthorized = true
                        DispatchQueue.global(qos: .userInitiated).async {
                            self?.setup()
                        }
                    }
                }
            }
        default:
            self.isCameraAuthorized = false
        }
    }
    
    func setup() {
        do {
            session.beginConfiguration()
            
            // Remove any existing inputs and outputs
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                print("Failed to get camera device")
                return
            }
            
            // Configure camera for high quality photo capture
            try device.lockForConfiguration()
            
            // Select highest resolution format that supports photo capture
            let formats = device.formats.filter { format in
                format.isHighestPhotoQualitySupported &&
                CMFormatDescriptionGetMediaType(format.formatDescription) == kCMMediaType_Video
            }
            
            if let bestFormat = formats.max(by: { first, second in
                let firstDimensions = CMVideoFormatDescriptionGetDimensions(first.formatDescription)
                let secondDimensions = CMVideoFormatDescriptionGetDimensions(second.formatDescription)
                return firstDimensions.width * firstDimensions.height < secondDimensions.width * secondDimensions.height
            }) {
                device.activeFormat = bestFormat
                let dimensions = CMVideoFormatDescriptionGetDimensions(bestFormat.formatDescription)
                print("Selected camera format: \(dimensions.width)x\(dimensions.height)")
            }
            
            device.unlockForConfiguration()
            
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            if session.canAddOutput(output) {
                session.addOutput(output)
                
                // Configure photo output for maximum quality
                output.maxPhotoQualityPrioritization = .quality
                
                // Enable high resolution capture
                output.isHighResolutionCaptureEnabled = true
            }
            
            session.sessionPreset = .photo
            
            session.commitConfiguration()
            
            if !session.isRunning {
                session.startRunning()
            }
        } catch {
            print("Failed to setup camera: \(error.localizedDescription)")
        }
    }
    
    deinit {
        if session.isRunning {
            session.stopRunning()
        }
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let imageData = photo.fileDataRepresentation(),
           let image = UIImage(data: imageData) {
            DispatchQueue.main.async {
                self.recentImage = image
                self.isPhotoTaken = true
                self.session.stopRunning()
            }
        }
    }
    
    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            print("Error saving photo: \(error.localizedDescription)")
        } else {
            print("Photo saved successfully")
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode
    @Binding var selectedImage: UIImage?
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// Add these utility functions before ContentView
private struct ViewUtilities {
    static func calculateImageSize(geometry: GeometryProxy, image: UIImage, isLandscape: Bool) -> CGSize {
        let containerWidth = geometry.size.width
        let containerHeight = geometry.size.height
        let imageAspectRatio = image.size.width / image.size.height
        
        if isLandscape {
            let maxHeight = containerHeight * 0.9 // 90% of container height
            let width = maxHeight * imageAspectRatio
            if width <= containerWidth {
                return CGSize(width: width, height: maxHeight)
            } else {
                let maxWidth = containerWidth * 0.9 // 90% of container width
                return CGSize(width: maxWidth, height: maxWidth / imageAspectRatio)
            }
        } else {
            let maxWidth = containerWidth * 0.9 // 90% of container width
            let height = maxWidth / imageAspectRatio
            if height <= containerHeight {
                return CGSize(width: maxWidth, height: height)
            } else {
                let maxHeight = containerHeight * 0.9 // 90% of container height
                return CGSize(width: maxHeight * imageAspectRatio, height: maxHeight)
            }
        }
    }
    
    static func cardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.appGradientStart.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 4)
    }
}

struct ZoomableImageView: View {
    let image: UIImage
    @Binding var shouldReset: Bool
    @Binding var isTransformed: Bool
    let isLandscape: Bool
    let cornerRadius: CGFloat
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var rotation: Angle = .zero
    @State private var lastRotation: Angle = .zero
    
    private func checkTransformation() {
        isTransformed = scale != 1.0 || offset != .zero || rotation != .zero
    }
    
    var body: some View {
        GeometryReader { geometry in
            let size = ViewUtilities.calculateImageSize(geometry: geometry, image: image, isLandscape: isLandscape)
            
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .scaleEffect(scale)
                .offset(offset)
                .rotationEffect(rotation)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                .gesture(
                    SimultaneousGesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale = scale * delta
                                    checkTransformation()
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                },
                            RotationGesture()
                                .onChanged { value in
                                    let delta = value - lastRotation
                                    lastRotation = value
                                    rotation += delta
                                    checkTransformation()
                                }
                                .onEnded { _ in
                                    lastRotation = .zero
                                }
                        ),
                        DragGesture()
                            .onChanged { value in
                                let delta = CGSize(
                                    width: value.translation.width - lastOffset.width,
                                    height: value.translation.height - lastOffset.height
                                )
                                lastOffset = value.translation
                                offset = CGSize(
                                    width: offset.width + delta.width,
                                    height: offset.height + delta.height
                                )
                                checkTransformation()
                            }
                            .onEnded { _ in
                                lastOffset = .zero
                            }
                    )
                )
                .highPriorityGesture(
                    TapGesture(count: 2)
                        .onEnded {
                            withAnimation(.spring()) {
                                scale = 1.0
                                offset = .zero
                                rotation = .zero
                            }
                            checkTransformation()
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in }
                )
                .onChange(of: shouldReset) { newValue in
                    if newValue {
                        withAnimation(.spring()) {
                            scale = 1.0
                            offset = .zero
                            rotation = .zero
                        }
                        shouldReset = false
                        checkTransformation()
                    }
                }
        }
    }
}

struct DeviceRotationViewModifier: ViewModifier {
    let action: (UIDeviceOrientation) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear()
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                action(UIDevice.current.orientation)
            }
    }
}

extension View {
    func onRotate(perform action: @escaping (UIDeviceOrientation) -> Void) -> some View {
        self.modifier(DeviceRotationViewModifier(action: action))
    }
}

// Camera preview container view
private struct CameraPreviewContainer: View {
    let geometry: GeometryProxy
    let isLandscape: Bool
    let session: AVCaptureSession
    let videoOrientation: AVCaptureVideoOrientation
    let controls: () -> AnyView
    
    var body: some View {
        let maxWidth = geometry.size.width * 0.9
        let maxHeight = geometry.size.height * 0.9
        
        ZStack {
            // Camera preview
            CameraPreview(session: session, videoOrientation: videoOrientation)
                .frame(width: maxWidth, height: maxHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .background(ViewUtilities.cardBackground(cornerRadius: 12))
            
            // Controls overlay positioned relative to the full container
            AnyView(controls())
        }
    }
}

// Captured photo view
private struct CapturedPhotoView: View {
    let image: UIImage
    let cornerRadius: CGFloat
    let photoActions: () -> AnyView
    
    var body: some View {
        GeometryReader { geometry in
            let size = ViewUtilities.calculateImageSize(geometry: geometry, image: image, isLandscape: false)
            
            ZStack {
                // Photo preview with consistent size
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .background(ViewUtilities.cardBackground(cornerRadius: cornerRadius))
                
                // Bottom-right buttons
                VStack {
                    HStack {
                        Spacer()
                        AnyView(photoActions())
                    }
                    Spacer()
                }
            }
            .position(x: geometry.size.width/2, y: geometry.size.height/2)
        }
    }
}

// Add InfoView struct before ContentView
private struct InfoView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var camera: CameraModel
    
    private var appIcon: UIImage? {
        if let iconsDictionary = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primaryIconsDictionary = iconsDictionary["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primaryIconsDictionary["CFBundleIconFiles"] as? [String],
           let lastIcon = iconFiles.last {
            return UIImage(named: lastIcon)
        }
        return nil
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    if let icon = appIcon {
                        Image(uiImage: icon)
                            .resizable()
                            .frame(width: 80, height: 80)
                            .cornerRadius(16)
                    } else {
                        // Fallback to app name if icon is not found
                        Text("ES")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 80, height: 80)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.appGradientStart)
                            )
                    }
                    
                    VStack(spacing: 16) {
                        Text("EchoSnap")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.appGradientStart)
                        
                        Text("© 2025 nerdyStuff")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(spacing: 12) {
                        Link(destination: URL(string: "https://www.nerdystuff.xyz")!) {
                            HStack {
                                Text("About Us")
                                Spacer()
                                Image(systemName: "arrow.up.right.circle.fill")
                            }
                            .foregroundColor(.appGradientStart)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.appGradientStart.opacity(0.1))
                            )
                        }
                        
                        Link(destination: URL(string: "https://www.nerdystuff.xyz/pages/contact-us")!) {
                            HStack {
                                Text("Contact")
                                Spacer()
                                Image(systemName: "arrow.up.right.circle.fill")
                            }
                            .foregroundColor(.appGradientStart)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.appGradientStart.opacity(0.1))
                            )
                        }
                        
                        Link(destination: URL(string: "https://buymeacoffee.com/nerdystuff")!) {
                            HStack {
                                Image(systemName: "cup.and.saucer.fill")
                                Text("Buy Me a Coffee")
                                Spacer()
                                Image(systemName: "arrow.up.right.circle.fill")
                            }
                            .foregroundColor(.appGradientStart)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(camera.photoCount >= 5 ? 
                                        Color.appGradientStart.opacity(0.2) :
                                        Color.appGradientStart.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(camera.photoCount >= 5 ? 
                                                Color.appGradientStart.opacity(0.3) :
                                                Color.clear,
                                                lineWidth: 2)
                                    )
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 0)
                }
                .padding(.top, 40)
                .frame(maxWidth: 400) // Fixed maximum width
                .frame(maxHeight: .infinity)
                .padding(.horizontal)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Forces modal style in all orientations
        .onDisappear {
            // Reset counter when info view is dismissed
            camera.resetPhotoCount()
        }
    }
}

// Add JumpingCoffeeIcon view before ContentView
private struct JumpingCoffeeIcon: View {
    @State private var isJumping = false
    
    var body: some View {
        Image(systemName: "cup.and.saucer.fill")
            .font(.system(size: 24))
            .foregroundColor(.appGradientStart)
            .offset(y: isJumping ? -5 : 0)
            .animation(
                Animation.easeInOut(duration: 0.5)
                    .repeatForever(autoreverses: true),
                value: isJumping
            )
            .onAppear {
                isJumping = true
            }
    }
}

struct ContentView: View {
    @State private var showImagePicker = false
    @State private var referenceImage: UIImage?
    @State private var shouldResetImage = false
    @State private var isImageTransformed = false
    @StateObject private var camera = CameraModel()
    @State private var orientation = UIDevice.current.orientation
    @State private var showInfoView = false
    
    private let buttonSize: CGFloat = 24
    private let captureButtonSize: CGFloat = 60
    private let buttonSpacing: CGFloat = 12  // Spacing between buttons
    private let standardPadding: CGFloat = 16  // Standard padding for all edges
    private let bannerHeight: CGFloat = 30  // Height for the title banner
    private let cardPadding: CGFloat = 12
    private let cardSpacing: CGFloat = 4
    private let cardCornerRadius: CGFloat = 12
    
    private var isLandscape: Bool {
        // Get the interface orientation instead of device orientation
        let interfaceOrientation = UIWindow.key?.windowScene?.interfaceOrientation ?? .portrait
        return interfaceOrientation.isLandscape
    }
    
    private var videoOrientation: AVCaptureVideoOrientation {
        // Get the interface orientation instead of device orientation
        let interfaceOrientation = UIWindow.key?.windowScene?.interfaceOrientation ?? .portrait
        
        switch interfaceOrientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return .portrait
        }
    }
    
    private func handleOrientationChange(_ newOrientation: UIDeviceOrientation) {
        // Only handle actual orientation changes that match interface orientations
        if orientation != newOrientation {
            switch newOrientation {
            case .portrait, .landscapeLeft, .landscapeRight:
                orientation = newOrientation
                
                // Only handle camera preview if it's active and no photo is taken
                if camera.isPreviewActive && !camera.isPhotoTaken {
                    camera.isPreviewActive = false
                    camera.session.stopRunning()
                    
                    // Reopen camera preview after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        camera.togglePreview()
                    }
                }
            default:
                // Ignore other orientations (face up, face down, portrait upside down)
                break
            }
        }
    }
    
    // Helper view for the photo action buttons
    private func photoActionButtons() -> some View {
        VStack(spacing: buttonSpacing) {
            Button(action: {
                withAnimation(.spring()) {
                    camera.savePhotoAndReopen()
                }
            }) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: buttonSize))
                    .foregroundColor(.white)
                    .background(
                        Circle()
                            .fill(Color.appGradientStart)
                            .frame(width: buttonSize + 8, height: buttonSize + 8)
                    )
            }
            
            Button(action: {
                withAnimation(.spring()) {
                    camera.discardPhotoAndReopen()
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: buttonSize))
                    .foregroundColor(.white)
                    .background(
                        Circle()
                            .fill(Color.red.opacity(0.8))
                            .frame(width: buttonSize + 8, height: buttonSize + 8)
                    )
            }
        }
        .padding(standardPadding)
    }
    
    // Helper view for the reference image buttons
    private func referenceImageButtons() -> some View {
        HStack(spacing: buttonSpacing) {
            if isImageTransformed {
                Button(action: {
                    shouldResetImage = true
                }) {
                    Image(systemName: "arrow.counterclockwise.circle")
                        .font(.system(size: buttonSize))
                        .foregroundColor(.appGradientStart)
                }
                .padding([.bottom, .trailing], standardPadding)
            }
        }
    }
    
    // Helper view for the camera preview controls
    private func cameraPreviewControls() -> some View {
        ZStack {
            // Camera preview with capture button
            VStack {
                Spacer()
                Button(action: {
                    camera.capturePhoto()
                }) {
                    Circle()
                        .fill(Color.appGradientStart)
                        .frame(width: captureButtonSize, height: captureButtonSize)
                        .shadow(color: .black.opacity(0.2), radius: 4)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .padding(4)
                        )
                }
                .padding(.bottom, standardPadding)
            }
            
            // Top-right close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation(.spring()) {
                            camera.togglePreview()
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: buttonSize))
                            .foregroundColor(.white)
                            .background(
                                Circle()
                                    .fill(Color.red.opacity(0.8))
                                    .frame(width: buttonSize + 8, height: buttonSize + 8)
                            )
                    }
                    .padding(standardPadding)
                }
                Spacer()
            }
        }
    }
    
    // Add title banner view
    private func titleBanner() -> some View {
        ZStack {
            // Title centered in the entire space, ignoring other elements
            Text("EchoSnap")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.appGradientStart)
            
            // Info/Coffee button aligned to the trailing edge
            HStack {
                Spacer()
                Button(action: { showInfoView = true }) {
                    if camera.photoCount >= 5 {
                        JumpingCoffeeIcon()
                    } else {
                        Image(systemName: "info.circle")
                            .font(.system(size: buttonSize))
                            .foregroundColor(.appGradientStart)
                    }
                }
                .frame(width: 44)  // Fixed width for the button area
            }
        }
        .frame(height: bannerHeight)
        .padding(.horizontal, cardPadding)
    }
    
    // Add a custom modifier for landscape padding
    private struct LandscapePaddingModifier: ViewModifier {
        let isLandscape: Bool
        
        func body(content: Content) -> some View {
            content
        }
    }
    
    // Add a new view for the enhanced placeholder:
    private struct EnhancedPlaceholder: View {
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.appGradientStart)
                    
                    Text("Tap to Select Reference Image")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.appGradientStart)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.appGradientStart.opacity(0.3), lineWidth: 2)
                        )
                )
                .padding(20)
            }
        }
    }
    
    // Simplify EnhancedCameraPlaceholder
    private struct EnhancedCameraPlaceholder: View {
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                VStack(spacing: 16) {
                    Image(systemName: "camera.circle.fill")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.appGradientStart)
                    
                    Text("Tap to Open Camera")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.appGradientStart)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.appGradientStart.opacity(0.3), lineWidth: 2)
                        )
                )
                .padding(20)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            titleBanner()
            
            GeometryReader { geometry in
                if isLandscape {
                    // Landscape layout
                    HStack(spacing: cardSpacing) {
                        // Left half: Reference Image
                        ZStack {
                            ViewUtilities.cardBackground(cornerRadius: cardCornerRadius)
                            
                            if let referenceImage = referenceImage {
                                ZStack {
                                    ZoomableImageView(
                                        image: referenceImage,
                                        shouldReset: $shouldResetImage,
                                        isTransformed: $isImageTransformed,
                                        isLandscape: true,
                                        cornerRadius: cardCornerRadius
                                    )
                                    
                                    // Bottom-right buttons
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Spacer()
                                            referenceImageButtons()
                                        }
                                    }
                                    
                                    // Top-right close button
                                    VStack {
                                        HStack {
                                            Spacer()
                                            Button(action: {
                                                withAnimation(.spring()) {
                                                    self.referenceImage = nil
                                                }
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: buttonSize))
                                                    .foregroundColor(.white)
                                                    .background(
                                                        Circle()
                                                            .fill(Color.red.opacity(0.8))
                                                            .frame(width: buttonSize + 8, height: buttonSize + 8)
                                                    )
                                            }
                                            .padding(standardPadding)
                                        }
                                        Spacer()
                                    }
                                }
                            } else {
                                EnhancedPlaceholder(action: { showImagePicker = true })
                            }
                        }
                        .frame(width: (geometry.size.width - cardSpacing - cardPadding * 2 - 32) / 2)  // Account for both left and right margins
                        
                        // Right half: Camera
                        ZStack {
                            ViewUtilities.cardBackground(cornerRadius: cardCornerRadius)
                            
                            if !camera.isPreviewActive {
                                EnhancedCameraPlaceholder(action: { camera.togglePreview() })
                            } else if let capturedImage = camera.recentImage, camera.isPhotoTaken {
                                CapturedPhotoView(
                                    image: capturedImage,
                                    cornerRadius: cardCornerRadius,
                                    photoActions: { AnyView(photoActionButtons()) }
                                )
                            } else {
                                GeometryReader { geo in
                                    CameraPreviewContainer(
                                        geometry: geo,
                                        isLandscape: isLandscape,
                                        session: camera.session,
                                        videoOrientation: videoOrientation,
                                        controls: { AnyView(cameraPreviewControls()) }
                                    )
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                        }
                        .frame(width: (geometry.size.width - cardSpacing - cardPadding * 2 - 32) / 2)  // Account for both left and right margins
                    }
                    .padding(.horizontal, cardPadding)
                    .padding(.top, cardPadding)
                    .padding(.bottom, 16)  // Add bottom padding
                    .padding(.leading, 16) // Notch protection
                    .padding(.trailing, 16) // Right margin
                } else {
                    // Portrait layout
                    VStack(spacing: cardSpacing) {
                        // Top half: Reference Image
                        ZStack {
                            ViewUtilities.cardBackground(cornerRadius: cardCornerRadius)
                            
                            if let referenceImage = referenceImage {
                                ZStack {
                                    ZoomableImageView(
                                        image: referenceImage,
                                        shouldReset: $shouldResetImage,
                                        isTransformed: $isImageTransformed,
                                        isLandscape: false,
                                        cornerRadius: cardCornerRadius
                                    )
                                    
                                    // Bottom-right buttons
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Spacer()
                                            referenceImageButtons()
                                        }
                                    }
                                    
                                    // Top-right close button
                                    VStack {
                                        HStack {
                                            Spacer()
                                            Button(action: {
                                                withAnimation(.spring()) {
                                                    self.referenceImage = nil
                                                }
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: buttonSize))
                                                    .foregroundColor(.white)
                                                    .background(
                                                        Circle()
                                                            .fill(Color.red.opacity(0.8))
                                                            .frame(width: buttonSize + 8, height: buttonSize + 8)
                                                    )
                                            }
                                            .padding(standardPadding)
                                        }
                                        Spacer()
                                    }
                                }
                            } else {
                                EnhancedPlaceholder(action: { showImagePicker = true })
                            }
                        }
                        .frame(height: (geometry.size.height - cardSpacing - cardPadding * 2 - 16) / 2)
                        
                        // Bottom half: Camera
                        ZStack {
                            ViewUtilities.cardBackground(cornerRadius: cardCornerRadius)
                            
                            if !camera.isPreviewActive {
                                EnhancedCameraPlaceholder(action: { camera.togglePreview() })
                            } else if let capturedImage = camera.recentImage, camera.isPhotoTaken {
                                CapturedPhotoView(
                                    image: capturedImage,
                                    cornerRadius: cardCornerRadius,
                                    photoActions: { AnyView(photoActionButtons()) }
                                )
                            } else {
                                GeometryReader { geo in
                                    CameraPreviewContainer(
                                        geometry: geo,
                                        isLandscape: isLandscape,
                                        session: camera.session,
                                        videoOrientation: videoOrientation,
                                        controls: { AnyView(cameraPreviewControls()) }
                                    )
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                        }
                        .frame(height: (geometry.size.height - cardSpacing - cardPadding * 2 - 16) / 2)
                    }
                    .padding(.horizontal, cardPadding)
                    .padding(.top, cardPadding)
                    .padding(.bottom, 16)
                }
            }
        }
        .ignoresSafeArea(edges: [.horizontal, .bottom])
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $referenceImage)
        }
        .sheet(isPresented: $showInfoView) {
            InfoView(camera: camera)
        }
        .onRotate { newOrientation in
            handleOrientationChange(newOrientation)
        }
    }
}

#Preview {
    ContentView()
}

extension UIWindow {
    static var key: UIWindow? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return nil }
        return scene.windows.first(where: { $0.isKeyWindow })
    }
}
