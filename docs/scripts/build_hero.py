"""Rebuild the static README cover from real screenshots. Requires Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
IMAGES = ROOT / 'docs/images'
fonts = list(Path('/System/Library/AssetsV2').glob('com_apple_MobileAsset_Font*/*/AssetData/PingFang.ttc'))
font_path = str(fonts[0]) if fonts else '/System/Library/Fonts/STHeiti Medium.ttc'
def font(size): return ImageFont.truetype(font_path, size)
canvas = Image.new('RGB', (1600, 920))
pixels = canvas.load()
for y in range(920):
    for x in range(1600):
        t = max(0, 1 - ((x-1250)**2 + (y-280)**2)**0.5 / 1350)
        pixels[x,y] = (int(248-30*t), int(250-17*t), int(255-2*t))
d = ImageDraw.Draw(canvas)
d.rounded_rectangle((64,62,270,104), radius=21, fill='#e4edff')
d.text((84,68),'BDMenu 2.6.0', font=font(23), fill='#1763df')
icon = Image.open(IMAGES/'app-icon.png').convert('RGBA').resize((90,90))
canvas.paste(icon,(62,141),icon)
d.text((174,143),'BDMenu',font=font(70),fill='#12223b')
d.text((64,281),'让每块屏幕',font=font(61),fill='#12223b')
d.text((64,362),'都刚刚好。',font=font(61),fill='#12223b')
d.text((68,477),'亮度、布局与开合角度',font=font(28),fill='#435670')
d.text((68,522),'从菜单栏开始，跟随你的工作方式。',font=font(26),fill='#435670')
for i,label in enumerate(['角度自动切换','多屏配置记忆','实时 GPU 状态']):
    y=606+i*55
    d.ellipse((70,y+8,79,y+17),fill='#1677f0')
    d.text((97,y),label,font=font(26),fill='#243b59')

def screenshot(name,x,y,width):
    img = Image.open(IMAGES/name).convert('RGBA')
    img.thumbnail((width,760))
    shadow = Image.new('RGBA',canvas.size)
    sd=ImageDraw.Draw(shadow)
    sd.rounded_rectangle((x+5,y+14,x+img.width+5,y+img.height+14),radius=22,fill=(18,39,80,45))
    shadow=shadow.filter(ImageFilter.GaussianBlur(18))
    canvas.paste(shadow,(0,0),shadow)
    canvas.paste(img,(x,y),img)
screenshot('automation.png',1010,129,510)
screenshot('quick-panel.png',650,243,332)
d=ImageDraw.Draw(canvas)
d.text((67,842),'原生 SwiftUI + AppKit  ·  macOS 14+  ·  Apple Silicon',font=font(23),fill='#54647b')
d.text((1100,842),'真实界面 · 自定义参数示例',font=font(20),fill='#54647b')
canvas.save(IMAGES/'hero.png',optimize=True)
