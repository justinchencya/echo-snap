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

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let isLandscape: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    class VideoPreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }
        
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }
    }
    
    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.backgroundColor = colorScheme == .dark ? .black : .systemBackground
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspect
        
        // Set orientation based on device orientation
        if isLandscape {
            let deviceOrientation = UIDevice.current.orientation
            view.videoPreviewLayer.connection?.videoOrientation = deviceOrientation == .landscapeLeft ? .landscapeRight : .landscapeLeft
        } else {
            view.videoPreviewLayer.connection?.videoOrientation = .portrait
        }
        
        return view
    }
    
    func updateUIView(_ uiView: VideoPreviewView, context: Context) {
        DispatchQueue.main.async {
            uiView.backgroundColor = colorScheme == .dark ? .black : .systemBackground
            uiView.videoPreviewLayer.frame = uiView.bounds
            
            // Update orientation based on device orientation
            if isLandscape {
                let deviceOrientation = UIDevice.current.orientation
                uiView.videoPreviewLayer.connection?.videoOrientation = deviceOrientation == .landscapeLeft ? .landscapeRight : .landscapeLeft
            } else {
                uiView.videoPreviewLayer.connection?.videoOrientation = .portrait
            }
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
                camera.discardPhotoAndReopen()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: buttonSize))
                    .foregroundColor(.red)
                    .background(Circle().fill(Color.white))
            }
            
            Button(action: {
                camera.savePhotoAndReopen()
            }) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: buttonSize))
                    .foregroundColor(.green)
                    .background(Circle().fill(Color.white))
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
            }
            
            Button(action: {
                showImagePicker = true
            }) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: buttonSize))
                    .foregroundColor(.green)
                    .background(Circle().fill(Color.white))
            }
        }
        .padding([.bottom, .trailing], buttonPadding)
    }
    
    // Helper view for the captured photo with buttons
    private func capturedPhotoView(image: UIImage, in geometry: GeometryProxy) -> some View {
        let maxWidth = geometry.size.width * 0.9  // 90% of container width
        let maxHeight = geometry.size.height * 0.9  // 90% of container height
        
        return ZStack(alignment: .bottomTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: maxWidth)
                .frame(maxHeight: maxHeight)
                .position(x: geometry.size.width/2, y: geometry.size.height/2)
            
            photoActionButtons()
        }
    }
    
    // Helper view for the camera preview controls
    private func cameraPreviewControls() -> some View {
        GeometryReader { geometry in
            VStack {
                // Close button at top-right
                HStack {
                    Spacer()
                    Button(action: {
                        camera.togglePreview()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: buttonSize))
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    .padding([.top, .trailing], closeButtonPadding)
                }
                
                Spacer()
                
                // Capture button centered at bottom
                HStack {
                    Spacer()
                    Button(action: {
                        camera.capturePhoto()
                    }) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: captureButtonSize, height: captureButtonSize)
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.8), lineWidth: 2)
                                    .frame(width: captureButtonSize - 10, height: captureButtonSize - 10)
                            )
                    }
                    Spacer()
                }
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // Add title banner view
    private func titleBanner() -> some View {
        Text("EchoSnap")
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: bannerHeight)
            .background(Color.blue.opacity(0.8))
    }
    
    // Add background color properties
    @Environment(\.colorScheme) private var colorScheme
    
    private var sectionBackground: Color {
        colorScheme == .dark ? Color.black : Color(UIColor.systemBackground)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            titleBanner()
            
            Group {
                if isLandscape {
                    // Landscape layout
                    HStack(spacing: 0) {
                        // Left half: Reference Image
                        ZStack {
                            sectionBackground
                            
                            if let referenceImage = referenceImage {
                                ZStack(alignment: .bottomTrailing) {
                                    ZoomableImageView(image: referenceImage, shouldReset: $shouldResetImage, isLandscape: true)
                                    
                                    // Top-right close button
                                    VStack {
                                        HStack {
                                            Spacer()
                                            Button(action: {
                                                self.referenceImage = nil
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: buttonSize))
                                                    .foregroundColor(.white)
                                                    .background(Circle().fill(Color.black.opacity(0.5)))
                                            }
                                            .padding([.top, .trailing], closeButtonPadding)
                                        }
                                        Spacer()
                                    }
                                    
                                    // Bottom-right control buttons
                                    referenceImageButtons()
                                }
                            } else {
                                Button(action: {
                                    showImagePicker = true
                                }) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 80, height: 80)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .clipped()
                        
                        // Right half: Camera
                        ZStack {
                            sectionBackground
                            
                            if !camera.isPreviewActive {
                                Button(action: {
                                    camera.togglePreview()
                                }) {
                                    Image(systemName: "camera.circle.fill")
                                        .resizable()
                                        .frame(width: 60, height: 60)
                                        .foregroundColor(.blue)
                                }
                            } else if let capturedImage = camera.recentImage, camera.isPhotoTaken {
                                GeometryReader { geometry in
                                    capturedPhotoView(image: capturedImage, in: geometry)
                                }
                            } else {
                                GeometryReader { geometry in
                                    let availableHeight = geometry.size.height * 0.9  // 90% of container height
                                    let availableWidth = geometry.size.width * 0.9  // 90% of container width
                                    let height = availableHeight
                                    let width = min(height * 4/3, availableWidth)
                                    
                                    ZStack {
                                        CameraPreview(session: camera.session, isLandscape: isLandscape)
                                            .frame(width: width, height: height)
                                            .clipped()
                                            .position(x: geometry.size.width/2, y: geometry.size.height/2)
                                        
                                        cameraPreviewControls()
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    // Original vertical layout
                    VStack(spacing: 0) {
                        // Top half: Reference Image or Icon Button
                        ZStack {
                            sectionBackground
                            
                            if let referenceImage = referenceImage {
                                ZStack(alignment: .bottomTrailing) {
                                    ZoomableImageView(image: referenceImage, shouldReset: $shouldResetImage, isLandscape: false)
                                    
                                    // Top-right close button
                                    VStack {
                                        HStack {
                                            Spacer()
                                            Button(action: {
                                                self.referenceImage = nil
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: buttonSize))
                                                    .foregroundColor(.white)
                                                    .background(Circle().fill(Color.black.opacity(0.5)))
                                            }
                                            .padding([.top, .trailing], closeButtonPadding)
                                        }
                                        Spacer()
                                    }
                                    
                                    // Bottom-right control buttons
                                    referenceImageButtons()
                                }
                            } else {
                                Button(action: {
                                    showImagePicker = true
                                }) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 80, height: 80)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .frame(maxHeight: .infinity)
                        .clipped()
                        
                        // Bottom half: Camera Preview/Photo with Buttons
                        ZStack {
                            sectionBackground
                            
                            if !camera.isPreviewActive {
                                // Show camera icon when preview is off
                                Button(action: {
                                    camera.togglePreview()
                                }) {
                                    Image(systemName: "camera.circle.fill")
                                        .resizable()
                                        .frame(width: 60, height: 60)
                                        .foregroundColor(.blue)
                                }
                            } else if let capturedImage = camera.recentImage, camera.isPhotoTaken {
                                GeometryReader { geometry in
                                    capturedPhotoView(image: capturedImage, in: geometry)
                                }
                            } else {
                                // Show camera preview with correct aspect ratio
                                GeometryReader { geometry in
                                    let availableWidth = geometry.size.width * 0.9  // 90% of container width
                                    let availableHeight = geometry.size.height * 0.9  // 90% of container height
                                    let width = availableWidth
                                    let height = min(width * 4/3, availableHeight)
                                    
                                    ZStack {
                                        CameraPreview(session: camera.session, isLandscape: isLandscape)
                                            .frame(width: width, height: height)
                                            .clipped()
                                            .position(x: geometry.size.width/2, y: geometry.size.height/2)
                                        
                                        cameraPreviewControls()
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
            }
        }
        .ignoresSafeArea(edges: [.horizontal, .bottom])  // Fix safe area edges
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
