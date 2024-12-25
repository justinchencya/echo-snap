import React from 'react';

function DirectionalArrows({ guidance }) {
  const getArrowStyles = (direction) => {
    // Convert direction text to arrow position and rotation
    const styles = {
      position: 'absolute',
      width: '50px',
      height: '50px',
      border: '4px solid #007bff',
      borderTop: 'none',
      borderLeft: 'none',
      transform: 'rotate(45deg)',
      opacity: 0.8,
      transition: 'all 0.3s ease'
    };

    switch (direction?.toUpperCase()) {
      case 'HIGHER':
        return { ...styles, top: '20px', left: '50%', transform: 'rotate(-135deg)' };
      case 'LOWER':
        return { ...styles, bottom: '20px', left: '50%', transform: 'rotate(45deg)' };
      case 'LEFT':
        return { ...styles, left: '20px', top: '50%', transform: 'rotate(135deg)' };
      case 'RIGHT':
        return { ...styles, right: '20px', top: '50%', transform: 'rotate(-45deg)' };
      case 'CLOSER':
        return {
          ...styles,
          border: 'none',
          top: '50%',
          left: '50%',
          transform: 'translate(-50%, -50%)',
          background: 'url("data:image/svg+xml,%3Csvg xmlns=\'http://www.w3.org/2000/svg\' viewBox=\'0 0 24 24\' fill=\'%23007bff\'%3E%3Cpath d=\'M12 2L20 10H4L12 2Z M12 22L4 14H20L12 22Z\'/%3E%3C/svg%3E") center/contain no-repeat'
        };
      case 'FARTHER':
        return {
          ...styles,
          border: 'none',
          top: '50%',
          left: '50%',
          transform: 'translate(-50%, -50%) rotate(180deg)',
          background: 'url("data:image/svg+xml,%3Csvg xmlns=\'http://www.w3.org/2000/svg\' viewBox=\'0 0 24 24\' fill=\'%23007bff\'%3E%3Cpath d=\'M12 2L20 10H4L12 2Z M12 22L4 14H20L12 22Z\'/%3E%3C/svg%3E") center/contain no-repeat'
        };
      default:
        return { display: 'none' };
    }
  };

  return (
    <div className="directional-arrows">
      {guidance?.map((item, index) => {
        if (item.category === 'Angle' || item.category === 'Distance') {
          return (
            <div 
              key={index}
              className="arrow"
              style={getArrowStyles(item.direction)}
            />
          );
        }
        return null;
      })}
    </div>
  );
}

export default DirectionalArrows; 