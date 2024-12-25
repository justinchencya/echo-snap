import React, { useEffect, useRef, useState } from 'react';
import OpenAI from 'openai';

function CameraView({ referenceImage }) {
  const videoRef = useRef(null);
  const canvasRef = useRef(null);
  const [hasPermission, setHasPermission] = useState(false);
  const [guidance, setGuidance] = useState('');
  const [isAnalyzing, setIsAnalyzing] = useState(false);

  // Initialize OpenAI client
  const openai = new OpenAI({
    apiKey: process.env.REACT_APP_OPENAI_API_KEY,
    dangerouslyAllowBrowser: true // Note: In production, proxy through backend
  });

  const setupCamera = async () => {
    try {
      const constraints = {
        video: {
          facingMode: 'environment',
          width: { ideal: 1280 },
          height: { ideal: 720 }
        }
      };
      
      console.log('Requesting camera access...');
      const stream = await navigator.mediaDevices.getUserMedia(constraints);
      console.log('Camera access granted!');
      
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        videoRef.current.onloadedmetadata = () => {
          console.log('Video metadata loaded');
          videoRef.current.play()
            .then(() => {
              console.log('Video playback started');
              setHasPermission(true);
            })
            .catch(err => console.error('Video playback failed:', err));
        };
      }
    } catch (err) {
      console.error('Detailed camera error:', err);
      setHasPermission(false);
    }
  };

  useEffect(() => {
    setupCamera();
  }, []);

  const captureFrame = () => {
    if (!videoRef.current || !canvasRef.current) return null;
    
    const canvas = canvasRef.current;
    const video = videoRef.current;
    const context = canvas.getContext('2d');
    
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    context.drawImage(video, 0, 0, canvas.width, canvas.height);
    
    return canvas.toDataURL('image/jpeg');
  };

  const analyzeImages = async () => {
    if (isAnalyzing) return;
    setIsAnalyzing(true);

    try {
      const currentFrame = captureFrame();
      if (!currentFrame) {
        console.log('Failed to capture frame');
        return;
      }
      console.log('Sending request to OpenAI...');
      
      const response = await openai.chat.completions.create({
        model: "gpt-4-vision-preview",
        messages: [
          {
            role: "user",
            content: [
              {
                type: "text",
                text: "Compare these two images. The first is a reference photo, and the second is a live camera feed. Provide brief, clear guidance on how to move the camera to match the reference photo's angle and composition. Focus on directions like 'move left', 'tilt up', 'move closer', etc."
              },
              {
                type: "image_url",
                image_url: {
                  url: referenceImage,
                  detail: "low"
                }
              },
              {
                type: "image_url",
                image_url: {
                  url: currentFrame,
                  detail: "low"
                }
              },
            ],
          },
        ],
        max_tokens: 100,
      });

      console.log('Received guidance:', response.choices[0].message.content);
      setGuidance(response.choices[0].message.content);
    } catch (error) {
      console.error('Error analyzing images:', error);
      setGuidance('Error analyzing images: ' + error.message);
    } finally {
      setIsAnalyzing(false);
    }
  };

  // Analyze every 2 seconds
  useEffect(() => {
    if (!hasPermission) return;
    
    const interval = setInterval(analyzeImages, 2000);
    return () => clearInterval(interval);
  }, [hasPermission, referenceImage]);

  return (
    <div className="camera-view">
      <div className="reference-image">
        <img src={referenceImage} alt="Reference" />
      </div>
      <div className="camera-feed">
        {hasPermission ? (
          <>
            <video
              ref={videoRef}
              autoPlay
              playsInline
              style={{ width: '100%', height: 'auto' }}
            />
            <canvas ref={canvasRef} style={{ display: 'none' }} />
            <div className="guidance-overlay">
              {guidance}
            </div>
          </>
        ) : (
          <div>Camera permission denied or error occurred. Please check console for details.</div>
        )}
      </div>
    </div>
  );
}

export default CameraView; 