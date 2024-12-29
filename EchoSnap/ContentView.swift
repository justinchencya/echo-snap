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
    static let appBackground = Color(UIColor.systemBackground)
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
    let isLandscape: Bool
    
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
        
        return view
    }
    
    func updateUIView(_ uiView: PreviewView, context: Context) {
        if isLandscape {
            uiView.videoPreviewLayer.connection?.videoOrientation = .landscapeRight
        } else {
            uiView.videoPreviewLayer.connection?.videoOrientation = .portrait
        }
    }
}

class CameraModel: NSObject, ObservableObject {
    @Published var session = AVCaptureSession()
    @Published var recentImage: UIImage?
    @Published var isPhotoTaken = false
    @Published var isPreviewActive = false
    private var isCameraAuthorized = false
    private let output = AVCapturePhotoOutput()
    
    override init() {
        super.init()
        checkPermissions()
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
        
        if let photoOutputConnection = output.connection(with: .video) {
            let deviceOrientation = UIDevice.current.orientation
            switch deviceOrientation {
            case .landscapeLeft:
                photoOutputConnection.videoOrientation = .landscapeRight
            case .landscapeRight:
                photoOutputConnection.videoOrientation = .landscapeLeft
            case .portraitUpsideDown:
                photoOutputConnection.videoOrientation = .portraitUpsideDown
            default:
                photoOutputConnection.videoOrientation = .portrait
            }
        }
        
        output.capturePhoto(with: settings, delegate: self)
    }
    
    func retakePhoto() {
        recentImage = nil
        isPhotoTaken = false
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }
    }
    
    func deletePhoto() {
        recentImage = nil
        isPhotoTaken = false
        // Auto restart camera preview
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }
    }
    
    func savePhotoAndReopen() {
        if let image = recentImage {
            // Save to camera roll
            UIImageWriteToSavedPhotosAlbum(image, self, #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
        }
        // Clear and reopen camera
        recentImage = nil
        isPhotoTaken = false
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }
    }
    
    func discardPhotoAndReopen() {
        // Just clear and reopen camera without saving
        recentImage = nil
        isPhotoTaken = false
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }
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
            
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            
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

struct ZoomableImageView: View {
    let image: UIImage
    @Binding var shouldReset: Bool
    let isLandscape: Bool
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var rotation: Angle = .zero
    @State private var lastRotation: Angle = .zero
    
    var body: some View {
        GeometryReader { geometry in
            let size = calculateImageSize(geometry: geometry, image: image)
            
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
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
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                },
                            RotationGesture()
                                .onChanged { value in
                                    let delta = value - lastRotation
                                    lastRotation = value
                                    rotation += delta
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
                    }
                }
        }
    }
    
    private func calculateImageSize(geometry: GeometryProxy, image: UIImage) -> CGSize {
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
    let controls: () -> AnyView
    
    var body: some View {
        let maxWidth = geometry.size.width * 0.9  // 90% of container width
        let maxHeight = geometry.size.height * 0.9  // 90% of container height
        
        ZStack {
            // Card background
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.05))
                .shadow(color: .black.opacity(0.2), radius: 8)
                .frame(width: maxWidth, height: maxHeight)
            
            // Camera preview
            CameraPreview(session: session, isLandscape: isLandscape)
                .frame(width: maxWidth, height: maxHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            
            // Controls overlay
            AnyView(controls())
        }
        .position(x: geometry.size.width/2, y: geometry.size.height/2)
    }
}

// Captured photo view
private struct CapturedPhotoView: View {
    let image: UIImage
    let cornerRadius: CGFloat
    let photoActions: () -> AnyView
    
    var body: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            
            // Bottom-right buttons
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    AnyView(photoActions())
                }
            }
        }
    }
}

struct ContentView: View {
    @State private var showImagePicker = false
    @State private var referenceImage: UIImage?
    @State private var shouldResetImage = false
    @StateObject private var camera = CameraModel()
    @State private var orientation = UIDevice.current.orientation
    
    private let buttonSize: CGFloat = 24
    private let captureButtonSize: CGFloat = 60
    private let buttonSpacing: CGFloat = 12  // Spacing between buttons
    private let buttonPadding: CGFloat = 16  // Padding from edges
    private let closeButtonPadding: CGFloat = 16  // Padding for close button
    private let bannerHeight: CGFloat = 30  // Height for the title banner
    private let cardPadding: CGFloat = 12
    private let cardSpacing: CGFloat = 4
    private let cardCornerRadius: CGFloat = 12
    
    private var isLandscape: Bool {
        // Only consider left and right landscape orientations
        orientation == .landscapeLeft || orientation == .landscapeRight
    }
    
    private func handleOrientationChange(_ newOrientation: UIDeviceOrientation) {
        // Only handle actual orientation changes and ignore face up/down
        if orientation != newOrientation && !newOrientation.isFlat {
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
        }
    }
    
    // Helper view for the photo action buttons
    private func photoActionButtons() -> some View {
        HStack(spacing: buttonSpacing) {
            Button(action: {
                withAnimation(.spring()) {
                    camera.discardPhotoAndReopen()
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: buttonSize))
                    .foregroundColor(.red)
                    .background(Circle().fill(Color.white))
                    .shadow(color: .black.opacity(0.2), radius: 4)
            }
            
            Button(action: {
                withAnimation(.spring()) {
                    camera.savePhotoAndReopen()
                }
            }) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: buttonSize))
                    .foregroundColor(.green)
                    .background(Circle().fill(Color.white))
                    .shadow(color: .black.opacity(0.2), radius: 4)
            }
        }
        .padding([.bottom, .trailing], buttonPadding)
    }
    
    // Helper view for the reference image buttons
    private func referenceImageButtons() -> some View {
        HStack(spacing: buttonSpacing) {
            Button(action: {
                shouldResetImage = true
            }) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: buttonSize))
                    .foregroundColor(.blue)
                    .background(Circle().fill(Color.white))
                    .shadow(color: .black.opacity(0.2), radius: 4)
            }
            
            Button(action: {
                showImagePicker = true
            }) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: buttonSize))
                    .foregroundColor(.green)
                    .background(Circle().fill(Color.white))
                    .shadow(color: .black.opacity(0.2), radius: 4)
            }
        }
        .padding([.bottom, .trailing], buttonPadding)
    }
    
    // Helper view for the captured photo with buttons
    private func capturedPhotoView(image: UIImage, in geometry: GeometryProxy) -> some View {
        let maxWidth = geometry.size.width * 0.9  // 90% of container width
        let maxHeight = geometry.size.height * 0.9  // 90% of container height
        
        return ZStack(alignment: .bottomTrailing) {
            ZStack {
                // Card background
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.05))
                    .shadow(color: .black.opacity(0.2), radius: 8)
                    .frame(width: geometry.size.width * 0.9, height: geometry.size.height * 0.9)
                    .position(x: geometry.size.width/2, y: geometry.size.height/2)
                
                // Photo
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width * 0.9, height: geometry.size.height * 0.9)
                    .position(x: geometry.size.width/2, y: geometry.size.height/2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    .frame(width: geometry.size.width * 0.9, height: geometry.size.height * 0.9)
                    .position(x: geometry.size.width/2, y: geometry.size.height/2)
            )
            
            // Action buttons - now positioned at bottom-right
            photoActionButtons()
                .frame(width: geometry.size.width * 0.9, height: geometry.size.height * 0.9)
                .position(x: geometry.size.width/2, y: geometry.size.height/2)
        }
    }
    
    // Helper view for the camera preview controls
    private func cameraPreviewControls() -> some View {
        VStack {
            // Close button at top-right
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
                        .background(Circle().fill(Color.black.opacity(0.5)))
                        .shadow(color: .black.opacity(0.2), radius: 4)
                }
                .padding(closeButtonPadding)
            }
            
            Spacer()
            
            // Capture button centered at bottom
            Button(action: {
                camera.capturePhoto()
            }) {
                Circle()
                    .fill(Color.white)
                    .frame(width: captureButtonSize, height: captureButtonSize)
                    .shadow(color: .black.opacity(0.3), radius: 5)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.2), lineWidth: 2)
                            .padding(4)
                    )
            }
            .padding(.bottom, buttonPadding)
        }
    }
    
    // Add title banner view
    private func titleBanner() -> some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [.appGradientStart, .appGradientEnd]),
                startPoint: .leading,
                endPoint: .trailing
            )
            
            Text("EchoSnap")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(height: bannerHeight)
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
    
    // Add background color properties
    @Environment(\.colorScheme) private var colorScheme
    
    private var sectionBackground: Color {
        colorScheme == .dark ? Color.black : Color(UIColor.systemBackground)
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
                        .stroke(Color.appGradientStart.opacity(0.3), lineWidth: 2)
                        .background(Color.appGradientStart.opacity(0.05))
                        .cornerRadius(12)
                )
                .padding(20)
            }
        }
    }
    
    // Add enhanced camera placeholder
    private struct EnhancedCameraPlaceholder: View {
        let action: () -> Void
        @State private var isHovered = false
        
        var body: some View {
            Button(action: action) {
                VStack(spacing: 16) {
                    Image(systemName: "camera.circle.fill")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.appGradientStart)
                        .scaleEffect(isHovered ? 1.1 : 1.0)
                    
                    Text("Tap to Open Camera")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.appGradientStart)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.appGradientStart.opacity(0.3), lineWidth: 2)
                        .background(Color.appGradientStart.opacity(0.05))
                        .cornerRadius(12)
                )
                .padding(20)
            }
            .onHover { hovering in
                withAnimation(.spring()) {
                    isHovered = hovering
                }
            }
        }
    }
    
    // Helper function for consistent card styling
    private func cardBackground() -> some View {
        RoundedRectangle(cornerRadius: cardCornerRadius)
            .fill(Color.black.opacity(0.05))
            .shadow(color: .black.opacity(0.1), radius: 8)
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
                            cardBackground()
                            
                            if let referenceImage = referenceImage {
                                ZStack {
                                    ZoomableImageView(image: referenceImage, shouldReset: $shouldResetImage, isLandscape: true)
                                        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
                                    
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
                                                    .background(Circle().fill(Color.black.opacity(0.5)))
                                                    .shadow(color: .black.opacity(0.2), radius: 4)
                                            }
                                            .padding(closeButtonPadding)
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
                            cardBackground()
                            
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
                            cardBackground()
                            
                            if let referenceImage = referenceImage {
                                ZStack {
                                    ZoomableImageView(image: referenceImage, shouldReset: $shouldResetImage, isLandscape: false)
                                        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
                                    
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
                                                    .background(Circle().fill(Color.black.opacity(0.5)))
                                                    .shadow(color: .black.opacity(0.2), radius: 4)
                                            }
                                            .padding(closeButtonPadding)
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
                            cardBackground()
                            
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
        .onRotate { newOrientation in
            handleOrientationChange(newOrientation)
        }
    }
}

#Preview {
    ContentView()
}
