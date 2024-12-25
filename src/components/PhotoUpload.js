import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';

function PhotoUpload({ setReferenceImage }) {
  const [preview, setPreview] = useState(null);
  const navigate = useNavigate();

  const handleFileUpload = (event) => {
    const file = event.target.files[0];
    if (file) {
      const reader = new FileReader();
      reader.onloadend = () => {
        setPreview(reader.result);
        setReferenceImage(reader.result);
      };
      reader.readAsDataURL(file);
    }
  };

  const handleContinue = () => {
    if (preview) {
      navigate('/camera');
    }
  };

  return (
    <div className="photo-upload">
      <h2>Upload Reference Photo</h2>
      <input
        type="file"
        accept="image/*"
        onChange={handleFileUpload}
      />
      {preview && (
        <>
          <div className="preview">
            <img src={preview} alt="Preview" />
          </div>
          <button onClick={handleContinue}>Continue to Camera</button>
        </>
      )}
    </div>
  );
}

export default PhotoUpload; 