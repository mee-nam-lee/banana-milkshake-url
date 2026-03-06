import os
from dotenv import load_dotenv
load_dotenv()
import json
import base64
from typing import Optional, List
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from google import genai
from google.genai import types

app = FastAPI()

# Allow CORS for local dev
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

API_KEY = os.environ.get("GEMINI_API_KEY", os.environ.get("API_KEY"))
client = None

def get_client():
    global client
    if client is not None:
        return client
    
    current_key = os.environ.get("GEMINI_API_KEY", os.environ.get("API_KEY"))
    if not current_key:
        print("WARNING: GEMINI_API_KEY environment variable is not set. API calls will fail.")
        raise HTTPException(status_code=500, detail="GEMINI_API_KEY is not configured on the server.")
    
    try:
        client = genai.Client(api_key=current_key)
        return client
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to initialize Gemini Client: {str(e)}")

class ImageData(BaseModel):
    data: str
    mimeType: str

class AdCopy(BaseModel):
    headline: str
    description: str
    cta: str

class CopySuggestionRequest(BaseModel):
    copyType: str
    currentCopy: str

class EditAdRequest(BaseModel):
    baseImage: str
    prompt: str

class GenerateLifestyleRequest(BaseModel):
    productImage: ImageData
    prompt: str
    aspectRatio: str
    referenceImage: Optional[ImageData] = None

class GenerateAdsRequest(BaseModel):
    productImage: ImageData
    styleImage: ImageData
    logoImage: ImageData
    adCopy: AdCopy
    aspectRatio: str

class GenerateSingleAdRequest(BaseModel):
    productImage: ImageData
    styleImage: ImageData
    logoImage: ImageData
    adCopy: AdCopy
    aspectRatio: str
    creativeDirection: str

def handle_gemini_error(e: Exception):
    import logging
    logging.exception("Error in Gemini API")
    if hasattr(e, "message"):
        msg = str(e.message).lower()
        if "quota" in msg or "resource_exhausted" in msg:
            raise HTTPException(status_code=429, detail="API Quota Exceeded (out of tokens).")
        if "safety" in msg:
            raise HTTPException(status_code=400, detail="SAFETY_VIOLATION: Request blocked due to content policy.")
    raise HTTPException(status_code=500, detail=f"We have encountered problems in generating your assets: {str(e)}")


@app.post("/api/get-copy-suggestion")
async def get_copy_suggestion(req: CopySuggestionRequest):
    limits = {
        "headline": 35,
        "description": 200,
        "cta": 25,
    }
    limit = limits.get(req.copyType, 50)
    prompt = f'You are an expert ad copywriter. Refine the following ad {req.copyType} to be more concise and engaging, while staying true to the original intent. The new {req.copyType} must be under {limit} characters. Do not add any extra commentary, just return the refined text. Original {req.copyType}: "{req.currentCopy}"'
    model = "gemini-2.5-flash"

    try:
        response = await get_client().aio.models.generate_content(
            model=model,
            contents=prompt
        )
        return {"result": response.text.strip().replace('"', '')}
    except Exception as e:
        handle_gemini_error(e)

@app.post("/api/edit-ad")
async def edit_ad(req: EditAdRequest):
    model = "gemini-3.0-pro"  # changed to latest valid Python SDK model alias (often gemini-3.0-pro or gemini-2.5-pro for images, original logic says gemini-3-pro-image-preview)
    # The original Code says 'gemini-3-pro-image-preview'
    # We will use exactly what's requested if genai supports it.
    model = "gemini-3-pro-image-preview"

    editPrompt = f'''
**Persona:** You are an expert AI Graphic Designer performing a precise edit on an existing image. You are not creating a new image from scratch.

**Task:** Modify the provided ad image *only* as described in the user's instructions. You must follow the instructions literally.

**CRITICAL RULES:**
1.  **Minimal Change:** Change *only* what is explicitly requested. Preserve all other parts of the image, including quality, composition, and existing text (unless the instruction is to change that text).
2.  **Literal Interpretation:** Do not add your own creative elements or interpretations. If the instruction is "make the logo 10% bigger," do exactly that and nothing else.
3.  **Preserve Quality:** The output image must maintain the same resolution and quality as the input image. Avoid introducing artifacts or blurriness.

**User Instructions:** "{req.prompt}"
'''
    try:
        import re
        match = re.match(r"^data:(image/.+);base64,(.+)$", req.baseImage)
        if not match:
            raise HTTPException(status_code=400, detail="Invalid base image data URL format.")
        mime_type = match.group(1)
        data = match.group(2)
        
        image_part = types.Part.from_bytes(
            data=base64.b64decode(data),
            mime_type=mime_type
        )
        
        response = await get_client().aio.models.generate_content(
            model=model,
            contents=[image_part, editPrompt],
            config=types.GenerateContentConfig(response_modalities=["IMAGE"])
        )
        
        # In the new google-genai sdk, the generated image bytes are accessible via response.candidates[0].content.parts[0].inline_data.data
        if response.candidates and response.candidates[0].content and response.candidates[0].content.parts:
            # Look for the image part
            for p in response.candidates[0].content.parts:
                if p.inline_data:
                    out_b64 = base64.b64encode(p.inline_data.data).decode("utf-8")
                    out_mime = p.inline_data.mime_type
                    return {"result": f"data:{out_mime};base64,{out_b64}"}
        
        raise Exception("Model response did not contain a valid image part for the edit.")
    except Exception as e:
        handle_gemini_error(e)


@app.post("/api/generate-lifestyle-image")
async def generate_lifestyle_image(req: GenerateLifestyleRequest):
    model = "gemini-3-pro-image-preview"

    contents = []
    
    prod_data = base64.b64decode(req.productImage.data)
    prod_part = types.Part.from_bytes(data=prod_data, mime_type=req.productImage.mimeType)

    if req.referenceImage:
        fullPrompt = f'''
        **Persona:** You are an expert photo editor and retoucher with a mastery of photorealistic image composition.
        **Primary Objective:** Seamlessly and realistically integrate the user's "Product Photo" into the provided "Lifestyle Image Reference". The final output must look like a single, authentic photograph.
        **User Instructions:** "{req.prompt}"
        **Execution Plan:**
        1.  **Analyze and Isolate:** Carefully identify the primary product in the "Product Photo". Isolate the product completely.
        2.  **Integrate and Composite:** Place the product into the "Lifestyle Image Reference" according to the user's instructions.
        3.  **Maintain Realism (CRITICAL):** The integration must be flawless. Adjust lighting, shadows, reflections, and perspective.
        4.  **Final Polish:** High-resolution, photorealistic composition.
        **Critical Rules:**
        - **PRODUCT INTEGRITY (CRITICAL):** The product from the "Product Photo" MUST be integrated pixel-perfect identical to the original image. DO NOT alter its shape, branding, color, or any specific details under any circumstances.
        - **No Labels.**
        '''
        ref_data = base64.b64decode(req.referenceImage.data)
        ref_part = types.Part.from_bytes(data=ref_data, mime_type=req.referenceImage.mimeType)
        
        contents = [
            "**Product Photo:**", prod_part,
            "\\n\\n**Lifestyle Image Reference:**", ref_part,
            f"\\n\\n**Instructions:**\\n{fullPrompt}"
        ]
    else:
        fullPrompt = f'''
        **Persona:** You are an expert photo editor and retoucher.
        **Primary Objective:** Seamlessly place the product from the user-provided image into a new, photorealistic lifestyle scene based on the user's prompt.
        **User Prompt:** "{req.prompt}"
        **Execution Plan:**
        1.  **Isolate the Product:** 
        2.  **Create the Scene:** 
        3.  **Composite:**
        4.  **Final Polish:**
        **Critical Rule:** The product itself must remain pixel-perfect identical to the original image. DO NOT alter its shape, branding, color, or details under any circumstances.
        '''
        contents = [prod_part, fullPrompt]

    try:
        response = await get_client().aio.models.generate_content(
            model=model,
            contents=contents,
            config=types.GenerateContentConfig(response_modalities=["IMAGE"])
        )
        
        if response.candidates and response.candidates[0].content and response.candidates[0].content.parts:
            for p in response.candidates[0].content.parts:
                if p.inline_data:
                    out_b64 = base64.b64encode(p.inline_data.data).decode("utf-8")
                    out_mime = p.inline_data.mime_type
                    return {"result": {"data": out_b64, "mimeType": out_mime}}
        raise Exception("No image was generated")
    except Exception as e:
        handle_gemini_error(e)


styleVariations = [
    "**Image-Centric Focus:** The Product/Lifestyle Photo (ASSET 1) is the undisputed hero. Create a clean, minimalist layout where ASSET 1 is placed centrally and dominates the space. Use ASSET 1 as a strictly immutable foreground layer—DO NOT stretch, warp, redraw, or outpaint its pixels. Generate a complementary background that sits strictly behind ASSET 1. All other elements (text, logo) must be positioned with subtlety to support the image. The final feel should be premium and uncluttered.",
    "**Bold Typographic Focus:** Create a dynamic, modern layout where typography is a key artistic element. The design should be a balanced interplay between the untouched Product/Lifestyle Photo (ASSET 1) and large, impactful text. Use color blocks intelligently to separate text from the image. ASSET 1 MUST remain exactly as provided, completely unchanged and undistorted. The result should feel energetic and deliberate.",
    """**High-Fidelity Template Adaptation:** Your primary goal is to recreate the layout of the "Brand Style Guide/Ad Template" (ASSET 2) using the provided assets.
    1. Analyze the template's layout (image areas, text, logo).
    2. Construct a new ad with this structure, but insert ASSET 1 natively without altering ASSET 1's shape or internal pixels at all. Do not force ASSET 1 into unnatural masking shapes if it distorts it.
    3. REMOVE all original templates' words and pictures. The final ad must strictly preserve ASSET 1's visual integrity while borrowing ONLY the structural layout of ASSET 2."""
]

async def generate_single_ad(req: GenerateAdsRequest, creative_direction: str):
    model = "gemini-3-pro-image-preview"
    #model = 'gemini-3.1-flash-image-preview';
    has_copy = bool(req.adCopy.headline.strip())
    
    ad_copy_text = ""
    if has_copy:
        parts = []
        parts.append(f'  - Headline: "{req.adCopy.headline}"')
        parts.append(f'  - Description: "{req.adCopy.description}"')
        if req.adCopy.cta.strip():
            parts.append(f'  - Call to Action (CTA): "{req.adCopy.cta}"')
        ad_copy_text = "\\n".join(parts)
    else:
        ad_copy_text = "  - Skipped. The user will add their own text later."

    prompt = f'''
# ROLE & GOAL
You are an expert AI Art Director. Your goal is to create one professional, high-quality digital image ad using the provided assets and instructions.

# ASSETS
You will be provided with three images and optional text copy.
- **ASSET 1: Product/Lifestyle Photo:** The main visual for the ad.
- **ASSET 2: Brand Style Guide/Ad Template:** A reference for style ONLY.
- **ASSET 3: Brand Logo:** The official brand logo.
- **Ad Copy:**
{ad_copy_text}

# CREATIVE DIRECTION
For this specific ad, follow this direction: {creative_direction}

# EXECUTION RULES
Follow these rules meticulously.

### 1. How to Use the Style Guide (ASSET 2)
- **USE ONLY THE STYLE:** Extract and use only the stylistic elements from ASSET 2:
    - Color palette
    - Typography (font styles, weights)
    - General layout and design ideas (shapes, patterns).
- **DO NOT USE THE CONTENT (CRITICAL):** You are strictly forbidden from using any of the original *content* from ASSET 2. All of the following must be completely removed and ignored:
    - **Any logos.**
    - **Any text and ad copy.**
    - **Any existing products.**
    - **Any images.**
- The final ad must be a new creation inspired only by the *style* of ASSET 2.

### 2. Image Integration (ASSET 1)
- **CRITICAL: PIXEL-PERFECT PRESERVATION:**
    - Treat the product image within ASSET 1 as an **immutable source of truth**. You must use the original source pixels of the product.
    - **DO NOT** re-draw, re-light, clean up, or "hallucinate" any details on the product itself.
    - **MAINTAIN ASPECT RATIO:** Do not stretch, squash, or distort the product to fit the layout.

- **If ASSET 1 is a Product Photo (on a simple background):** - Extract the product using a precise mask. **Do not erode or blur the product edges.** Place it directly into your new ad composition while maintaining its original visual fidelity.

- **If ASSET 1 is a Lifestyle Photo:** Your goal is to create a visually engaging lifestyle ad that promotes the product within the photo by using one of the two methods below:
  - ** Method 1: Outpainting (Background Extension).** Seamlessly extend the **surrounding environment/background** to fill the relevant space. 
    - **STRICT CONSTRAINT:** During outpainting, the pixels corresponding to the **product and the model** must remain **locked and untouched**. Only the empty canvas areas should be generated.
  - ** Method 2: Composition.** If outpainting is not feasible, isolate the key person and product as a single layer. Use graphical elements, colors, and textures inspired by ASSET 2 to create a cohesive design.
    - **STRICT CONSTRAINT:** Ensure the graphical elements interact with the subject **without ever obscuring or overlapping the product itself.**

### 3. Logo Integration (ASSET 3)
- **CRITICAL RULE:** Treat ASSET 3 (the Brand Logo) as an immutable digital asset. It MUST be placed directly onto the final ad without ANY modification.
- **DO NOT RE-DRAW, RE-INTERPRET, OR TRACE THE LOGO.** You are strictly forbidden from altering the logo's pixels. This includes its colors, shape, proportions, and design elements. It must be a perfect copy.
- **VISIBILITY IS KEY (CRITICAL):** Place the logo in a professional, standard location (e.g., a corner). The logo **must** be clearly legible. To ensure this, it must have high contrast against its immediate background.
- Ensure the logo is legible but not dominant, occupying roughly 5-10% of the ad area.

### 4. Text Integration
'''
    if has_copy:
        prompt += '''
- Render the provided ad copy using the typography found in the "Brand Style Guide" (ASSET 2).
- If a copy element like 'Description' is not provided in the list above, do not invent one or create a placeholder for it.
- Ensure all text is perfectly legible with high contrast against its background.
- Use only the exact ad copy provided. Do not add, omit, or change any words.
'''
    else:
        prompt += '''
- **Create Natural Negative Space:** Since ad copy is skipped, design a visually complete ad with clean, uncluttered areas where text and ad copy could be added in later. This space should be an organic part of the design.
- **NO PLACEHOLDERS (CRITICAL):** Do not create any shapes that look like text placeholders (e.g., empty boxes or rectangles). Also, do not attempt to add your own text since no copy is explicitely provided. The ad must look like a polished, text-free visual, that is ready for the end user to add their own copy at a later stage.
'''

    prompt += '''
# FINAL QUALITY CHECK
Before finishing, verify:
1.  **No Obstruction:** No text, graphical elements, or logos cover any human faces or the product in the final image ad.
2.  **Professional Finish:** The ad is clean, sharp, and high-resolution. It should look like a digital image ad that is professionally designed with well composed and placed visual elements.
3.  **NO solid borders:** The ad MUST NOT have any odd solid borders at the sides or top/bottom.
4.  **Asset Integrity:** The brand logo (ASSET 3) is an exact, pixel-for-pixel copy. **Crucially, the Product (ASSET 1) is 100% authentic to the source file: no hallucinations, no distorted text/labels on the product, and no altered proportions.**
5.  **Rule Compliance:** You have followed all the execution rules above.
'''

    prod_part = types.Part.from_bytes(data=base64.b64decode(req.productImage.data), mime_type=req.productImage.mimeType)
    style_part = types.Part.from_bytes(data=base64.b64decode(req.styleImage.data), mime_type=req.styleImage.mimeType)
    logo_part = types.Part.from_bytes(data=base64.b64decode(req.logoImage.data), mime_type=req.logoImage.mimeType)

    contents = [
        '**ASSET 1: "Product/Lifestyle Photo"**', prod_part,
        '\\n\\n**ASSET 2: "Brand Style Guide/Ad Template"**', style_part,
        '\\n\\n**ASSET 3: "Brand Logo"**', logo_part,
        prompt
    ]

    client = get_client()
    response = await client.aio.models.generate_content(
        model=model,
        contents=contents,
        config=types.GenerateContentConfig(response_modalities=["IMAGE"])
    )
    
    if response.candidates and response.candidates[0].content and response.candidates[0].content.parts:
        for p in response.candidates[0].content.parts:
            if p.inline_data:
                out_b64 = base64.b64encode(p.inline_data.data).decode("utf-8")
                out_mime = p.inline_data.mime_type
                return f"data:{out_mime};base64,{out_b64}"
                
    raise Exception("Model response did not contain a valid image part.")

@app.post("/api/generate-ads")
async def generate_ads(req: GenerateAdsRequest):
    import asyncio
    
    # We will use an asyncio semaphore to limit parallel requests if needed (e.g. max 3)
    sem = asyncio.Semaphore(3)
    async def bounded_generate(direction):
        async with sem:
            return await generate_single_ad(req, direction)

    try:
        tasks = [bounded_generate(variation) for variation in styleVariations]
        results = await asyncio.gather(*tasks)
        return {"results": list(results)}
    except Exception as e:
        handle_gemini_error(e)

@app.post("/api/generate-single-ad")
async def api_generate_single_ad(req: GenerateSingleAdRequest):
    limits = {
        "headline": 35,
        "description": 200,
        "cta": 25,
    }
    for field, limit in limits.items():
        val = getattr(req.adCopy, field, "")
        if len(val) > limit:
            raise HTTPException(status_code=400, detail=f"{field.capitalize()} exceeds maximum length of {limit} characters.")

    ads_req = GenerateAdsRequest(
        productImage=req.productImage,
        styleImage=req.styleImage,
        logoImage=req.logoImage,
        adCopy=req.adCopy,
        aspectRatio=req.aspectRatio
    )
    result = await generate_single_ad(ads_req, req.creativeDirection)
    return {"result": result}

# Mount the static site for Cloud Run if the directory exists
import os
STATIC_DIR = os.path.join(os.path.dirname(__file__), "static")
if os.path.exists(STATIC_DIR):
    app.mount("/", StaticFiles(directory=STATIC_DIR, html=True), name="static")
else:
    @app.get("/")
    def index():
        return {"message": "API is running. Static frontend not found (run Vite dev server locally)."}
