import React, { useState } from 'react';
import OpenAI from 'openai';
import ImageOverlay from './ImageOverlay';

function ImageComparison() {
  const [referenceImage, setReferenceImage] = useState(null);
  const [compareImage, setCompareImage] = useState(null);
  const [guidance, setGuidance] = useState([]);
  const [isAnalyzing, setIsAnalyzing] = useState(false);

  // Initialize OpenAI client
  const openai = new OpenAI({
    apiKey: process.env.REACT_APP_OPENAI_API_KEY,
    dangerouslyAllowBrowser: true
  });

  const handleImageUpload = (event, setImage) => {
    const file = event.target.files[0];
    if (file) {
      // Check if the file type is supported
      const supportedTypes = ['image/png', 'image/jpeg', 'image/gif', 'image/webp'];
      if (!supportedTypes.includes(file.type)) {
        alert('Please upload a supported image format (PNG, JPEG, GIF, or WebP)');
        return;
      }

      const reader = new FileReader();
      reader.onloadend = () => {
        // Convert to JPEG format for consistency
        const img = new Image();
        img.onload = () => {
          const canvas = document.createElement('canvas');
          canvas.width = img.width;
          canvas.height = img.height;
          
          const ctx = canvas.getContext('2d');
          ctx.drawImage(img, 0, 0);
          
          // Convert to JPEG format
          const jpegDataUrl = canvas.toDataURL('image/jpeg', 0.8);
          setImage(jpegDataUrl);
        };
        img.src = reader.result;
      };
      reader.readAsDataURL(file);
    }
  };

  const analyzeImages = async () => {
    if (!referenceImage || !compareImage || isAnalyzing) return;
    setIsAnalyzing(true);

    try {
      const refImageBase64 = referenceImage.split(',')[1];
      const compImageBase64 = compareImage.split(',')[1];

      const response = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [
          {
            role: "system",
            content: "You are a photo comparison expert. Your task is to guide the user on how to adjust their comparison photo to match the reference photo. Provide clear, actionable directions from the user's perspective."
          },
          {
            role: "user",
            content: [
              {
                type: "text",
                text: "Compare these two photos. The first is the reference photo (goal), and the second is the user's current photo. Tell the user what actions they need to take to make their photo match the reference.\n\nProvide guidance in exactly this format:\n\nAngle - [ACTION USER NEEDS TO TAKE] | [detailed explanation]\nDistance - [ACTION USER NEEDS TO TAKE] | [detailed explanation]\nComposition - [ACTION USER NEEDS TO TAKE] | [detailed explanation]\nLighting - [ACTION USER NEEDS TO TAKE] | [detailed explanation]\n\nExample format:\nAngle - LOWER | Move your camera down by about 15 degrees\nDistance - CLOSER | Step forward about 2 feet\n\nUse | as separator. The action should be a single word describing what the user needs to do (e.g., LOWER, HIGHER, CLOSER, FARTHER, LEFT, RIGHT, etc.)."
              },
              {
                type: "image_url",
                image_url: {
                  url: `data:image/jpeg;base64,${refImageBase64}`
                }
              },
              {
                type: "image_url",
                image_url: {
                  url: `data:image/jpeg;base64,${compImageBase64}`
                }
              },
            ],
          },
        ],
        max_tokens: 300,
      });

      // Parse and format the response into an array of objects
      const content = response.choices[0].message.content;
      console.log('API Response:', content); // Debug log

      const guidanceItems = content
        .split('\n')
        .filter(line => line.trim() && line.includes('-'))
        .map(line => {
          const [category, fullGuidance] = line.split('-').map(str => str.trim());
          const [direction, details] = fullGuidance.split('|').map(str => str.trim());
          return {
            category,
            direction: direction || 'N/A',
            details: details || 'No specific guidance provided'
          };
        });

      console.log('Parsed guidance:', guidanceItems); // Debug log
      
      // If no guidance items were parsed, provide default structure
      if (guidanceItems.length === 0) {
        setGuidance([
          { category: 'Angle', direction: '...', details: 'Waiting for analysis...' },
          { category: 'Distance', direction: '...', details: 'Waiting for analysis...' },
          { category: 'Composition', direction: '...', details: 'Waiting for analysis...' },
          { category: 'Lighting', direction: '...', details: 'Waiting for analysis...' }
        ]);
      } else {
        setGuidance(guidanceItems);
      }

    } catch (error) {
      console.error('Error analyzing images:', error);
      setGuidance([{ category: 'Error', direction: 'ERROR', details: error.message }]);
    } finally {
      setIsAnalyzing(false);
    }
  };

  return (
    <div className="image-comparison">
      <h1>Photo Comparison Guide</h1>
      
      <div className="upload-section">
        <div className="upload-container">
          <h2>Reference Photo</h2>
          <input
            type="file"
            accept="image/*"
            onChange={(e) => handleImageUpload(e, setReferenceImage)}
          />
          {referenceImage && (
            <div className="image-preview">
              <img src={referenceImage} alt="Reference" />
            </div>
          )}
        </div>

        <div className="upload-container">
          <h2>Comparison Photo</h2>
          <input
            type="file"
            accept="image/*"
            onChange={(e) => handleImageUpload(e, setCompareImage)}
          />
          {compareImage && (
            <div className="image-preview">
              <img src={compareImage} alt="Comparison" />
            </div>
          )}
        </div>
      </div>

      {referenceImage && compareImage && (
        <>
          <ImageOverlay 
            referenceImage={referenceImage} 
            compareImage={compareImage}
          />
          <button 
            onClick={analyzeImages} 
            disabled={isAnalyzing}
            className="analyze-button"
          >
            {isAnalyzing ? 'Analyzing...' : 'Analyze Photos'}
          </button>
        </>
      )}

      {guidance.length > 0 && (
        <div className="guidance-container">
          {guidance.map((item, index) => (
            <div key={index} className="guidance-row">
              <span className="guidance-category">{item.category}</span>
              <span className="guidance-direction">{item.direction}</span>
              <span className="guidance-details">{item.details}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export default ImageComparison; 