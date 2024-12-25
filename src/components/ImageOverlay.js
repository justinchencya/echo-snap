import React, { useState } from 'react';

function ImageOverlay({ referenceImage, compareImage }) {
  const [referenceOpacity, setReferenceOpacity] = useState(0);

  return (
    <div className="overlay-container">
      <div className="overlay-images">
        <div className="image-stack">
          <img 
            src={compareImage}
            alt="Comparison" 
            className="base-image"
          />
          <img 
            src={referenceImage}
            alt="Reference" 
            className="overlay-image"
            style={{ opacity: referenceOpacity }}
          />
        </div>
      </div>
      <div className="overlay-controls">
        <input
          type="range"
          min="0"
          max="1"
          step="0.1"
          value={referenceOpacity}
          onChange={(e) => setReferenceOpacity(e.target.value)}
          className="opacity-slider"
        />
        <span className="opacity-label">{Math.round(referenceOpacity * 100)}% Reference</span>
      </div>
    </div>
  );
}

export default ImageOverlay; 