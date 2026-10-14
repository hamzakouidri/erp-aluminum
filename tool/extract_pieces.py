import cv2
import numpy as np
from PIL import Image

def process_item_1():
    # Image 1: Tasso / Taquet d'assemblage / Clam
    path = r'C:\Users\hp\.gemini\antigravity\brain\92232c31-5e1b-43c6-a423-9c94ff425343\.user_uploaded\media_1791919892693_9b1a3678.png'
    img = cv2.imread(path)
    h, w = img.shape[:2]

    # The metallic piece is held in hand in center: roughly x in [250, 520], y in [120, 720]
    # In HSV: hands are skin color (Hue 0-25, Saturation 40-200), metal is grey/desaturated (low saturation)
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    h_c, s_c, v_c = cv2.split(hsv)

    # Initial mask based on bounding box
    rect = (250, 120, 270, 600)
    mask = np.zeros((h, w), np.uint8)
    bgdModel = np.zeros((1, 65), np.float64)
    fgdModel = np.zeros((1, 65), np.float64)

    cv2.grabCut(img, mask, rect, bgdModel, fgdModel, 5, cv2.GC_INIT_WITH_RECT)
    
    # Metal has low saturation compared to reddish hand
    # Force high saturation areas outside the metal center to definite background
    metal_core_mask = (mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD)
    # Further refine with color: metal is silvery (low saturation < 65)
    metal_mask = metal_core_mask & (s_c < 75)
    
    # Morphological cleaning
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
    metal_clean = cv2.morphologyEx(metal_mask.astype(np.uint8), cv2.MORPH_CLOSE, kernel)
    metal_clean = cv2.morphologyEx(metal_clean, cv2.MORPH_OPEN, kernel)
    
    # Keep largest contour
    contours, _ = cv2.findContours(metal_clean, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if contours:
        c = max(contours, key=cv2.contourArea)
        final_mask = np.zeros((h, w), np.uint8)
        cv2.drawContours(final_mask, [c], -1, 255, -1)
        # Smooth mask edge
        final_mask = cv2.GaussianBlur(final_mask, (5, 5), 0)
        
        # Bounding rect with padding
        x, y, bw, bh = cv2.boundingRect(c)
        pad = 20
        x0, y0 = max(0, x - pad), max(0, y - pad)
        x1, y1 = min(w, x + bw + pad), min(h, y + bh + pad)
        
        crop_img = img[y0:y1, x0:x1]
        crop_alpha = final_mask[y0:y1, x0:x1]
        
        b, g, r = cv2.split(crop_img)
        rgba = cv2.merge([b, g, r, crop_alpha])
        
        out_path = r'assets\sections\tasso_assemblage.png'
        cv2.imwrite(out_path, rgba)
        print(f"Saved Image 1 to {out_path}")

def process_item_2():
    # Image 2: Patte de fixation / Support d'ancrage
    path = r'C:\Users\hp\.gemini\antigravity\brain\92232c31-5e1b-43c6-a423-9c94ff425343\.user_uploaded\media_1791919920394_139b7b4c.png'
    img = cv2.imread(path)
    h, w = img.shape[:2]

    # Metal piece in hand roughly x in [180, 590], y in [210, 680]
    rect = (180, 200, 420, 500)
    mask = np.zeros((h, w), np.uint8)
    bgdModel = np.zeros((1, 65), np.float64)
    fgdModel = np.zeros((1, 65), np.float64)

    cv2.grabCut(img, mask, rect, bgdModel, fgdModel, 5, cv2.GC_INIT_WITH_RECT)
    
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    h_c, s_c, v_c = cv2.split(hsv)
    
    metal_core = (mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD)
    metal_mask = metal_core & (s_c < 75)
    
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
    metal_clean = cv2.morphologyEx(metal_mask.astype(np.uint8), cv2.MORPH_CLOSE, kernel)
    metal_clean = cv2.morphologyEx(metal_clean, cv2.MORPH_OPEN, kernel)
    
    contours, _ = cv2.findContours(metal_clean, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if contours:
        c = max(contours, key=cv2.contourArea)
        final_mask = np.zeros((h, w), np.uint8)
        cv2.drawContours(final_mask, [c], -1, 255, -1)
        final_mask = cv2.GaussianBlur(final_mask, (5, 5), 0)
        
        x, y, bw, bh = cv2.boundingRect(c)
        pad = 20
        x0, y0 = max(0, x - pad), max(0, y - pad)
        x1, y1 = min(w, x + bw + pad), min(h, y + bh + pad)
        
        crop_img = img[y0:y1, x0:x1]
        crop_alpha = final_mask[y0:y1, x0:x1]
        
        b, g, r = cv2.split(crop_img)
        rgba = cv2.merge([b, g, r, crop_alpha])
        
        out_path = r'assets\sections\patte_fixation.png'
        cv2.imwrite(out_path, rgba)
        print(f"Saved Image 2 to {out_path}")

if __name__ == '__main__':
    process_item_1()
    process_item_2()
