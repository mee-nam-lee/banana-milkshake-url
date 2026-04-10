import React, { useState } from 'react';

interface ImagePickerPopupProps {
  isOpen: boolean;
  onClose: () => void;
  onSelect: (imageUrl: string) => void;
  category: 'product' | 'style' | 'logo' | null;
}

const IMAGE_MAP = {
  product: [
    'https://raw.githubusercontent.com/mee-nam-lee/gemini-enterprise-lab/refs/heads/main/static/milkshake/product/product_ac.png',
    'https://raw.githubusercontent.com/mee-nam-lee/gemini-enterprise-lab/refs/heads/main/static/milkshake/product/product_fridge_colorful.jpg',
    'https://raw.githubusercontent.com/mee-nam-lee/gemini-enterprise-lab/refs/heads/main/static/milkshake/product/product_fridge_white.png',
    'https://raw.githubusercontent.com/mee-nam-lee/gemini-enterprise-lab/refs/heads/main/static/milkshake/product/product_laundry.png',
    'https://raw.githubusercontent.com/mee-nam-lee/gemini-enterprise-lab/refs/heads/main/static/milkshake/product/product_purifier.png',
    'https://raw.githubusercontent.com/mee-nam-lee/gemini-enterprise-lab/refs/heads/main/static/milkshake/product/product_standbyme.png',
    'https://raw.githubusercontent.com/mee-nam-lee/gemini-enterprise-lab/refs/heads/main/static/milkshake/product/product_tv.png',
  ],
  style: [
    'https://raw.githubusercontent.com/mee-nam-lee/gemini-enterprise-lab/refs/heads/main/static/milkshake/style/style_ac_livingroom.png',
    'https://raw.githubusercontent.com/mee-nam-lee/gemini-enterprise-lab/refs/heads/main/static/milkshake/style/style_bestshop.png',
    'https://raw.githubusercontent.com/mee-nam-lee/gemini-enterprise-lab/refs/heads/main/static/milkshake/style/style_fridge_yellow.jpeg',
    'https://raw.githubusercontent.com/mee-nam-lee/gemini-enterprise-lab/refs/heads/main/static/milkshake/style/style_purifier.png',
    'https://raw.githubusercontent.com/mee-nam-lee/gemini-enterprise-lab/refs/heads/main/static/milkshake/style/style_standbyme_model1.png',
    'https://raw.githubusercontent.com/mee-nam-lee/gemini-enterprise-lab/refs/heads/main/static/milkshake/style/style_standbyme_model2.png',
    'https://raw.githubusercontent.com/mee-nam-lee/gemini-enterprise-lab/refs/heads/main/static/milkshake/style/style_standbyme_nature.jpg',
    'https://raw.githubusercontent.com/mee-nam-lee/gemini-enterprise-lab/refs/heads/main/static/milkshake/style/style_tv.jpg',
  ],
  logo: [
    'https://raw.githubusercontent.com/mee-nam-lee/gemini-enterprise-lab/refs/heads/main/static/milkshake/logo/logo_en.png',
    'https://raw.githubusercontent.com/mee-nam-lee/gemini-enterprise-lab/refs/heads/main/static/milkshake/logo/logo_ko.png',
    'https://raw.githubusercontent.com/mee-nam-lee/gemini-enterprise-lab/refs/heads/main/static/milkshake/logo/logo_lifeisgood.png',
  ],
};

const ImagePickerPopup: React.FC<ImagePickerPopupProps> = ({ isOpen, onClose, onSelect, category }) => {
  const [previewImage, setPreviewImage] = useState<string | null>(null);

  if (!isOpen || !category) return null;

  const images = IMAGE_MAP[category] || [];

  const handleSelect = () => {
    if (previewImage) {
      onSelect(previewImage);
      setPreviewImage(null);
      onClose();
    }
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex justify-center items-center z-50">
      <div className="bg-white rounded-lg p-6 w-11/12 max-w-4xl max-h-[90vh] overflow-y-auto">
        <div className="flex justify-between items-center mb-4">
          <h2 className="text-xl font-bold capitalize">Select {category} Image</h2>
          <button onClick={onClose} className="text-gray-500 hover:text-gray-700">
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {previewImage ? (
          <div className="flex flex-col items-center">
            <div className="mb-4 max-h-[60vh] overflow-hidden">
              <img src={previewImage} alt="Preview" className="max-w-full max-h-full object-contain" />
            </div>
            <div className="flex space-x-4">
              <button
                onClick={() => setPreviewImage(null)}
                className="px-4 py-2 bg-gray-300 text-gray-700 rounded-md hover:bg-gray-400"
              >
                Back to Gallery
              </button>
              <button
                onClick={handleSelect}
                className="px-4 py-2 bg-[#4285F4] text-white rounded-md hover:bg-blue-600"
              >
                Select Image
              </button>
            </div>
          </div>
        ) : (
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-4">
            {images.map((url, index) => (
              <div
                key={index}
                className="border rounded-md overflow-hidden cursor-pointer hover:border-blue-500 transition-colors bg-gray-50 flex items-center justify-center"
                onClick={() => setPreviewImage(url)}
              >
                <img src={url} alt={`Option ${index}`} className="w-full h-32 object-contain" />
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};

export default ImagePickerPopup;
