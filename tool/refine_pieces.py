import cv2
import numpy as np

def refine_item_1():
    # Image 1: Tasso
    path = r'C:\Users\hp\.gemini\antigravity\brain\92232c31-5e1b-43c6-a423-9c94ff425343\.user_uploaded\media_1791919892693_9b1a3678.png'
    img = cv2.imread(path)
    h, w = img.shape[:2]

    # Convert to YCrCb and HSV for precise skin detection
    ycrcb = cv2.cvtColor(img, cv2.COLOR_BGR2YCrCb)
    cr = ycrcb[:, :, 1]
    cb = ycrcb[:, :, 2]
    
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    sat = hsv[:, :, 1]
    val = hsv[:, :, 2]
    
    # Skin has high Cr (typically > 140) and Cb around 90-130, and saturation > 40
    # Metal has low saturation (< 50) and Cr close to neutral (~128)
    is_skin = (cr > 138) & (sat > 45)
    
    # The metal piece is strictly in the central stripe
    in_box = np.zeros((h, w), dtype=bool)
    in_box[130:730, 270:520] = True
    
    # Metal candidate: in box, NOT skin, reasonable brightness
    is_metal = in_box & (~is_skin) & (val > 60)
    
    # Clean up
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
    clean = cv2.morphologyEx(is_metal.astype(np.uint8), cv2.MORPH_CLOSE, kernel)
    clean = cv2.morphologyEx(clean, cv2.MORPH_OPEN, kernel)
    
    # Find contours and pick the main vertical piece
    contours, _ = cv2.findContours(clean, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    main_contour = None
    max_area = 0
    for c in contours:
        x, y, bw, bh = cv2.boundingRect(c)
        area = cv2.contourArea(c)
        # piece is vertically elongated (aspect ratio bh/bw > 2.5) and central
        if area > max_area and bh > 200:
            max_area = area
            main_contour = c
            
    if main_contour is not None:
        mask = np.zeros((h, w), dtype=np.uint8)
        cv2.drawContours(mask, [main_contour], -1, 255, -1)
        # Smooth mask slightly
        mask = cv2.GaussianBlur(mask, (3, 3), 0)
        
        x, y, bw, bh = cv2.boundingRect(main_contour)
        pad = 15
        x0, y0 = max(0, x - pad), max(0, y - pad)
        x1, y1 = min(w, x + bw + pad), min(h, y + bh + pad)
        
        crop_img = img[y0:y1, x0:x1]
        crop_alpha = mask[y0:y1, x0:x1]
        
        b, g, r = cv2.split(crop_img)
        rgba = cv2.merge([b, g, r, crop_alpha])
        
        out_path = r'assets\sections\tasso_assemblage.png'
        cv2.imwrite(out_path, rgba)
        print("Item 1 refined successfully.")

def refine_item_2():
    # Image 2: Support / Patte
    path = r'C:\Users\hp\.gemini\antigravity\brain\92232c31-5e1b-43c6-a423-9c94ff425343\.user_uploaded\media_1791919920394_139b7b4c.png'
    img = cv2.imread(path)
    h, w = img.shape[:2]

    # Convert to YCrCb
    ycrcb = cv2.cvtColor(img, cv2.COLOR_BGR2YCrCb)
    cr = ycrcb[:, :, 1]
    
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    sat = hsv[:, :, 1]
    val = hsv[:, :, 2]
    
    # Floor background has low sat (< 30) and high brightness (val > 180)
    # Hand skin has high Cr (> 140) and high sat (> 50)
    # Galvanized steel metal has low sat (< 45), val between 90 and 200, Cr around 125-135
    
    is_skin = (cr > 140) & (sat > 45)
    is_floor = (val > 195) & (sat < 35) & (cr < 140)
    
    in_box = np.zeros((h, w), dtype=bool)
    in_box[210:900, 190:610] = True
    
    is_metal = in_box & (~is_skin) & (~is_floor) & (val > 50)
    
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (7, 7))
    clean = cv2.morphologyEx(is_metal.astype(np.uint8), cv2.MORPH_CLOSE, kernel)
    clean = cv2.morphologyEx(clean, cv2.MORPH_OPEN, kernel)
    
    contours, _ = cv2.findContours(clean, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if contours:
        c = max(contours, key=cv2.contourArea)
        mask = np.zeros((h, w), dtype=np.uint8)
        cv2.drawContours(mask, [c], -1, 255, -1)
        mask = cv2.GaussianBlur(mask, (3, 3), 0)
        
        x, y, bw, bh = cv2.boundingRect(c)
        pad = 15
        x0, y0 = max(0, x - pad), max(0, y - pad)
        x1, y1 = min(w, x + bw + pad), min(h, y + bh + pad)
        
        crop_img = img[y0:y1, x0:x1]
        crop_alpha = mask[y0:y1, x0:x1]
        
        b, g, r = cv2.split(crop_img)
        rgba = cv2.merge([b, g, r, crop_alpha])
        
        out_path = r'assets\sections\patte_fixation.png'
        cv2.imwrite(out_path, rgba)
        print("Item 2 refined successfully.")

if __name__ == '__main__':
    refine_item_1()
    refine_item_2()
