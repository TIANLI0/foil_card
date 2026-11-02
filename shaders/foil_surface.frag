#version 460 core
#include <flutter/runtime_effect.glsl>
precision highp float;

// SPDX-License-Identifier: MIT
// General image-surface material. No card-specific textures or layout rules.
uniform vec2 uSize;
uniform vec2 uLight;
uniform vec4 uArtXform;
uniform float uPattern;
uniform float uIntensity;
uniform float uScale;
uniform float uSeed;
uniform float uMaskMode;
uniform float uTexture;
uniform float uTextureStrength;
uniform float uGlare;
uniform float uActivity;
uniform float uHasFoil;
uniform float uPixelRatio;
uniform float uMaskChannel;
uniform vec4 uFoilRegion;
uniform float uDetailProtection;
uniform float uOpacity;
// Glitter controls for the twinkle pattern (see twinkle()).
uniform vec4 uGlitterA;
uniform vec4 uGlitterB;
uniform vec3 uGlitterC;
uniform sampler2D uArt;
uniform sampler2D uMask;
uniform sampler2D uFoil;
out vec4 fragColor;

const float TAU=6.28318530718;
float luma(vec3 c) { return dot(c,vec3(.2126,.7152,.0722)); }
float random(vec2 p) {
  vec3 q=fract(vec3(p.xyx)*vec3(.1031,.1030,.0973));
  q+=dot(q,q.yzx+33.33);
  return fract((q.x+q.y)*q.z);
}
vec3 film(float phase) {
  // A continuous, desaturated spectrum keeps baked artwork recognizable.
  return .5+.32*cos(TAU*(phase+vec3(0,.333333,.666667)));
}
vec3 softLight(vec3 b,vec3 s) {
  vec3 d=mix(sqrt(max(b,0.0)),((16.0*b-12.0)*b+4.0)*b,step(b,vec3(.25)));
  return mix(b-(1.0-2.0*s)*b*(1.0-b),b+(2.0*s-1.0)*(d-b),step(vec3(.5),s));
}
float ridge(float p) { return 1.0-abs(fract(p)*2.0-1.0); }
float gaussian(float distance,float width) {
  float x=distance/width;
  return exp(-x*x);
}
vec3 straightArt(vec2 q,vec3 fallback) {
  vec4 c=texture(uArt,clamp(q,0.0,1.0));
  return c.a>.01?c.rgb/c.a:fallback;
}
// Four independent values per cell from one hash (Hoskins' hash42).
vec4 hash4(vec2 p) {
  vec4 q=fract(vec4(p.xyxy)*vec4(.1031,.1030,.0973,.1099));
  q+=dot(q,q.wzxy+33.33);
  return fract((q.xxyz+q.yzzw)*q.zywx);
}
// Fully saturated: laser foil, unlike the desaturated film().
vec3 laser(float phase) {
  return .5+.5*cos(TAU*(phase+vec3(0,.333333,.666667)));
}

// Four-point star (an astroid), 0..1, `e` = edge softness.
float starBody(vec2 ad,float r,float e) {
  return 1.0-smoothstep(1.0-e,1.0+e,sqrt(ad.x/r)+sqrt(ad.y/r));
}
float dot2(vec2 v) { return dot(v,v); }
// Exact signed distance to a heart (Inigo Quilez): tip at the origin, lobes
// up (y up), about 1.1 tall and 1.2 wide. Exact, so edges stay crisp.
float sdHeart(vec2 p) {
  p.x=abs(p.x);
  if(p.y+p.x>1.0) return sqrt(dot2(p-vec2(.25,.75)))-.35355339;
  return sqrt(min(dot2(p-vec2(0,1)),dot2(p-.5*max(p.x+p.y,0.0))))*
    sign(p.x-p.y);
}
// 0 over where a portrait's face and head usually are (upper middle third),
// 1 elsewhere. Only the face is kept clear: motifs over clothing and the
// background read as print, over a face as a blemish. `frame` blends from
// everywhere (0) to clear of the face (1). `q` is a motif position in the
// shader's p space (short side 1, center 0).
float frameWeight(vec2 q,float frame) {
  float e=length((q-vec2(0,-.33))/vec2(.27,.33));
  return mix(1.0,smoothstep(.95,1.2,e),frame);
}

// Holographic motif glitter, as on printed flash cards: every star (or heart)
// is its own tiny grating with its own angle, so it flashes at its own tilt.
// Turning the card hands the light from motif to motif instead of sweeping
// one band over the field. Motifs sit on a staggered grid, like a print;
// their color is diffraction-like (a rainbow across the card and across each
// motif, moved by the angle), so lit neighbours are close in color and no
// motif is one flat tint. Optional fine dust in between.
// Stars and hearts behave the same; only the shape differs (hearts have a
// soft halo instead of cross rays).
// Controls: uGlitterA = density, size, sharpness, flare;
//           uGlitterB = dust, color, print, hue;
//           uGlitterC = motif (0 star, 1 heart), iridescence, frame.
// Returns the reflected light; `printed` is the faint silver print, visible
// at any angle.
vec3 twinkle(vec2 p,float px,out float printed) {
  float density=uGlitterA.x;
  float size=uGlitterA.y;
  float exponent=mix(2.0,18.0,uGlitterA.z);
  float flare=uGlitterA.w;
  float colorful=uGlitterB.y;
  // Iridescence: how far the viewing angle moves the color along the
  // spectrum (1: about one and a half turns corner to corner).
  float hue=uGlitterB.w+dot(uLight,vec2(.75,.5))*uGlitterC.y;
  bool heart=uGlitterC.x>.5;
  float frame=uGlitterC.z;
  vec3 shine=vec3(0);
  printed=0.0;

  float cells=6.5*uScale;
  vec2 g=(p+2.0)*cells;
  float pxCell=px*cells;
  // Flares reach past a cell, so neighbours are drawn too.
  for(int j=-1;j<=1;j++) {
    float row=floor(g.y)+float(j);
    float shift=.5*mod(row,2.0);
    float column=floor(g.x-shift);
    for(int i=-1;i<=1;i++) {
      vec2 cell=vec2(column+float(i),row);
      vec4 a=hash4(cell+uSeed*1.37);
      vec4 b=hash4(cell+uSeed*1.37+17.0);
      vec2 home=cell+vec2(.5+shift,.5)+(a.yz-.5)*.25;
      float present=step(1.0-density*frameWeight(home/cells-2.0,frame),a.x);
      if(present<=0.0) continue;
      vec2 d=g-home;
      float r=size*mix(.85,1.15,a.w);
      float glint=pow(max(0.0,cos(b.x*TAU+dot(uLight,vec2(2.9,2.1)))),
        exponent);
      float body;
      float glow;
      if(heart) {
        // Crisp outline from an exact distance; a soft halo while lit.
        float h=2.0*r;
        float sd=sdHeart(vec2(d.x,-d.y)/h+vec2(0,.52))*h;
        body=1.0-smoothstep(-pxCell,pxCell,sd);
        glow=(1.0-body)*exp(-max(sd,0.0)*max(sd,0.0)/(h*h*.01));
      } else {
        vec2 ad=abs(d);
        body=starBody(ad,r,max(pxCell/r,.02));
        float w=max(pxCell*.7,r*.07);
        float len=min(r*(1.5+6.0*glint),1.4);
        glow=max(exp(-ad.y*ad.y/(w*w))*max(0.0,1.0-ad.x/len),
                 exp(-ad.x*ad.x/(w*w))*max(0.0,1.0-ad.y/len));
        glow*=glow;
      }
      // Diffraction color, as on real holographic foil: a rainbow sweeping
      // across the card (so neighbours are close in color), a gradient across
      // each motif (never one flat tint) and the angle moving it all.
      // Across one motif the phase spans most of a rainbow, so its rays
      // disperse into spectra like a real diffraction sparkle.
      float phase=hue+dot(p,vec2(.55,.35))+dot(d,vec2(.9,.6))/r*.35+
        (b.y-.5)*.06;
      vec3 tint=mix(vec3(1),laser(phase),colorful);
      // Silver at the very peak of a glint.
      tint=mix(tint,vec3(1),.5*glint*glint);
      shine+=tint*glint*(body*1.1+glow*flare*.9);
      printed+=body;
    }
  }
  printed*=uGlitterB.z;

  // Dust: sparse fine specks, each with a sharper glint of its own.
  float dust=uGlitterB.x;
  if(dust>0.0) {
    float dustCells=58.0*uScale;
    vec2 dg=(p+2.0)*dustCells;
    vec2 dcell=floor(dg);
    vec4 c=hash4(dcell+uSeed*2.11+40.0);
    float dr=max(.2,1.6*px*dustCells);
    float dd=length(dg-(dcell+.5+(c.yz-.5)*.6));
    float speck=step(1.0-.5*dust*frameWeight(dcell/dustCells-2.0,frame),c.x)*
      (1.0-smoothstep(dr*.5,dr,dd));
    float dglint=pow(max(0.0,cos(c.w*TAU+dot(uLight,vec2(4.3,3.1)))),
      exponent+4.0);
    vec3 dtint=mix(vec3(1),laser(hue+dot(p,vec2(.55,.35))+(c.y-.5)*.1),
      colorful*.8);
    shine+=dtint*speck*dglint*1.2;
  }
  return shine;
}

void main() {
  vec2 frag=FlutterFragCoord().xy;
  vec2 uv=frag/uSize;
  vec2 artUV=uv*uArtXform.xy+uArtXform.zw;
  if(min(artUV.x,artUV.y)<0.0 || max(artUV.x,artUV.y)>1.0) {
    fragColor=vec4(0); return;
  }
  vec4 art=texture(uArt,artUV);
  if(art.a<=0.0) {fragColor=vec4(0);return;}
  vec3 base=art.rgb/art.a;
  vec2 unit=uSize/min(uSize.x,uSize.y);
  vec2 p=(uv-.5)*unit;
  vec2 light=uLight*.5*unit;
  vec2 delta=p-light;
  float near=exp(-dot(delta,delta)/.36);
  float highlight=exp(-dot(delta,delta)/.025);

  // Edge protection is measured from the flattened image itself. Transparent
  // neighbors fall back to the current color, preventing halos around cutouts.
  vec2 stepUV=2.0/uSize*uArtXform.xy;
  vec3 left=straightArt(artUV-vec2(stepUV.x,0),base);
  vec3 right=straightArt(artUV+vec2(stepUV.x,0),base);
  vec3 top=straightArt(artUV-vec2(0,stepUV.y),base);
  vec3 bottom=straightArt(artUV+vec2(0,stepUV.y),base);
  float edge=max(max(length(base-left),length(base-right)),
                 max(length(base-top),length(base-bottom)));
  float ink=smoothstep(.025,.22,luma(base));
  float protection=mix(1.0,(.22+.78*ink)*(1.0-.85*smoothstep(.10,.55,edge)),uDetailProtection);

  float coverage=step(uFoilRegion.x,uv.x)*step(uFoilRegion.y,uv.y)*
    step(uv.x,uFoilRegion.z)*step(uv.y,uFoilRegion.w);
  if(uMaskMode>.5) {
    vec4 m=texture(uMask,uv);
    float mask=uMaskChannel>.5?m.a:luma(m.rgb);
    if(uMaskMode>1.5) mask=m.a-mask;
    coverage*=mask;
  }
  float phase=dot(p,vec2(.68,.73))*1.7*uScale+
    dot(uLight,vec2(.38,.27))+uSeed*.071;
  vec3 color=film(phase);
  float band=pow(ridge(dot(p,vec2(.68,.73))*1.1*uScale+
    dot(uLight,vec2(.28,.19))),3.0);
  float reflection=.20+.55*band+.25*near;
  float strength=.65;
  float streak=pow(band,3.0);
  vec3 sparkle=vec3(0);
  vec3 metalColor=base;
  float metalCoverage=0.0;
  if(uPattern>12.5 && uPattern<13.5) {
    // Nacre: broad, low-saturation interference rather than rainbow stripes.
    float nacre=sin(p.x*3.0*uScale+sin(p.y*4.0*uScale)+uLight.x*2.0);
    color=mix(vec3(.72,.52,.64),vec3(.48,.72,.76),nacre*.5+.5);
    reflection=.35+.65*near;
    strength=.5;
    streak=pow(max(0.0,cos(p.x-p.y+uLight.y*2.0)),6.0)*.5;
  }
  if(uPattern>13.5 && uPattern<14.5) {
    // A triangular lattice, with a separate normal for each facet.
    vec2 grid=vec2(p.x-p.y*.57735,p.y*1.1547)*9.0*uScale;
    vec2 cell=floor(grid);
    float halfCell=step(1.0,fract(grid.x)+fract(grid.y));
    vec2 id=cell+vec2(halfCell*.37,halfCell*.73);
    float orientation=random(id+uSeed)*TAU;
    float facet=pow(max(0.0,cos(orientation+dot(uLight,vec2(2.2,1.7)))),6.0);
    color=film(random(id+3.0)+dot(uLight,vec2(.28,.2)));
    reflection=.18+.82*facet;
    streak=facet*(.25+.75*near);
    strength=.85;
  }
  if(uPattern>14.5 && uPattern<15.5) {
    // Optical disc: angular color fans, fine concentric diffraction rings.
    vec2 disc=p-vec2(-.12,.08);
    float radius=length(disc);
    float angle=atan(disc.y,disc.x);
    color=film(angle/TAU*3.0+radius*.8*uScale+uLight.x*.4);
    float fan=pow(abs(cos(angle-atan(uLight.y+.31,uLight.x+.23))),14.0);
    float grooves=.7+.3*cos(radius*180.0*uScale);
    reflection=.15+.85*fan*grooves;
    streak=fan*grooves;
    strength=.85;
  }
  if(uPattern>15.5 && uPattern<16.5) {
    // Wavy contours with a traveling crest and an independent spectrum.
    float wave=p.y*9.0*uScale+sin(p.x*7.0*uScale+uSeed)*.65;
    float crest=pow(ridge(wave+dot(uLight,vec2(.3,.65))),14.0);
    color=film(wave*.1+uLight.x*.3);
    reflection=.15+.85*crest;
    streak=crest*(.2+.8*near);
    strength=.7;
  }
  if(uPattern>16.5 && uPattern<17.5) {
    // Chunky foil: sparse offset diamonds, each with its own reflective angle.
    vec2 grid=(p+2.0)*24.0*uScale;
    vec2 cell=floor(grid);
    vec2 local=fract(grid)-.5;
    vec2 offset=vec2(random(cell+2.0),random(cell+6.0))-.5;
    local-=offset*.45;
    float piece=1.0-smoothstep(.22,.28,abs(local.x)+abs(local.y));
    piece*=step(.28,random(cell+uSeed));
    float facing=pow(max(0.0,cos(random(cell+uSeed+9.0)*TAU+
      dot(uLight,vec2(3.5,2.5)))),12.0);
    color=film(random(cell+4.0)+dot(uLight,vec2(.2,.3)));
    reflection=piece*(.3+.7*facing);
    streak=0.0;
    sparkle=(color+.3)*piece*facing*.65*(.3+.7*near);
    strength=.9;
  }
  if(uPattern>19.5 && uPattern<20.5) {
    // Narrow reflected strips on a clear laminate, not a painted overlay.
    float environment=dot(p,vec2(.72,.69))-dot(uLight,vec2(.62,.46));
    float stripe=(fract(environment*1.6*uScale+.5)-.5)/(1.6*uScale);
    float core=gaussian(stripe,.012);
    float glow=gaussian(stripe,.055);
    vec3 reflectedLight=vec3(.86,.96,1.0)*(.68*core+.28*glow);
    metalColor=base+(1.0-base)*reflectedLight;
    metalCoverage=1.0;
    color=vec3(.5); strength=0.0; reflection=0.0; streak=0.0;
  }
  if(uPattern>20.5 && uPattern<21.5) {
    // Broad translucent interference ribbons. Only reflected light is tinted;
    // there is no opaque colored fill across the image.
    float environment=(p.x+sin(p.y*3.0*uScale+uLight.y)*.15-uLight.x*.6)*uScale;
    float ribbon=gaussian(environment+.22,.14);
    float halo=gaussian(environment-.25,.3);
    vec3 tint=mix(vec3(.30,.92,.80),vec3(.68,.50,1.0),
      .5+.5*sin(p.y*2.0+uLight.y*1.5));
    metalColor=base+(1.0-base)*tint*(.5*ribbon+.32*halo);
    metalCoverage=1.0;
    color=vec3(.5); strength=0.0; reflection=0.0; streak=0.0;
  }
  if(uPattern>21.5 && uPattern<22.5) {
    // Twinkle: per-star glints (see twinkle()). A faint silver print keeps the
    // stars there at any angle. Glints are a little stronger where the light
    // falls, but never sweep the field as one band.
    float printed;
    vec3 shine=twinkle(p,1.0/(min(uSize.x,uSize.y)*max(uPixelRatio,1.0)),
      printed);
    sparkle=shine*(.6+.4*near)+vec3(.86,.89,.93)*min(printed,1.0)*.25;
    color=vec3(.5); strength=0.0; reflection=0.0; streak=0.0;
  }
  if(uPattern>17.5 && uPattern<19.5) {
    // Flat foil print. One reflected environment sweeps across the pattern;
    // no per-point normals, bevels, outlines or sculpted star faces.
    bool hearts=uPattern>18.5;
    vec2 grid=(p+2.0)*(hearts?9.0:11.0)*uScale;
    grid.x+=mod(floor(grid.y),2.0)*.5;
    vec2 cell=floor(grid);
    vec2 local=fract(grid)-.5;
    vec2 a=abs(local);
    float contour=sqrt(a.x)+sqrt(a.y);
    float motif=1.0-smoothstep(.46,.53,contour);
    if(hearts) {
      vec2 heart=vec2(local.x,-local.y)*4.0+vec2(0,.2);
      float d=dot(heart,heart)-1.0;
      float shape=d*d*d-heart.x*heart.x*heart.y*heart.y*heart.y;
      motif=1.0-smoothstep(-.05,.08,shape);
    }
    motif*=step(hearts ? .35 : .45,random(cell+uSeed));
    float environment=dot(p,vec2(.72,.69))-dot(uLight,vec2(.62,.46));
    vec3 distanceToBand=(vec3(environment)-vec3(.04,.04,-.48))/vec3(.25,.045,.12);
    // Multiplication is defined on both sides of the band; GLSL pow with a
    // negative base is undefined, even for an integer-valued exponent.
    vec3 bands=exp(-distanceToBand*distanceToBand);
    float broad=bands.x, core=bands.y, echo=bands.z;
    float grain=(random(floor((p+2.0)*700.0*uScale)+uSeed)-.5)*.008;
    vec3 tint=hearts?vec3(.66,.94,1.0):vec3(1.0);
    float reflectedLight=clamp(.36*broad+.64*core+.14*echo+grain,0.0,1.0);
    // Reflection modulates the underlying art instead of replacing it with
    // solid gray silhouettes. Off-angle marks are only very faintly visible.
    metalColor=base*(1.0-.045*(1.0-broad))+(1.0-base)*tint*reflectedLight;
    metalCoverage=motif*(.18+.65*broad+.17*core);
    color=vec3(.5);
    strength=0.0;
    reflection=0.0;
    streak=0.0;
  }
  if(uPattern<.5 || (uPattern>11.5 && uPattern<12.5)) {
    float brushed=random(vec2(floor(p.x*12.0),floor(p.y*420.0*uScale))+uSeed);
    color=mix(vec3(.43),vec3(.72,.73,.75),near);
    reflection=(.7+.3*brushed)*(.3+.7*near);
    strength=.35;
  }
  if(uPattern>3.5 && uPattern<4.5) {
    strength=0.0;
  }
  if(uPattern>5.5 && uPattern<6.5) {
    phase=p.x*2.7*uScale+uLight.x*.6+uLight.y*.12;
    color=film(phase);
    reflection=.2+.8*pow(ridge(p.x*3.2*uScale+uLight.x*.4),4.0);
  }
  if(uPattern>6.5 && uPattern<7.5) {
    float a=pow(ridge((p.x+p.y)*7.0*uScale+uLight.x*.4),8.0);
    float b=pow(ridge((p.x-p.y)*7.0*uScale-uLight.y*.4),8.0);
    reflection=(a+b)*.5*(.3+.7*near);
  }
  if(uPattern>10.5 && uPattern<11.5) {
    color=vec3(.73,.57,.30);
    strength=.7;
  }
  if(uPattern>2.5 && uPattern<3.5) {
    float cloud=sin(p.x*8.0+sin(p.y*4.0))*cos(p.y*7.0+sin(p.x*5.0));
    color=film(phase+cloud*.18);
    reflection=.35+cloud*.2+near*.45;
  }
  if((uPattern>1.5 && uPattern<3.5) || (uPattern>9.5 && uPattern<11.5)) {
    vec2 cell=floor((p+2.0)*180.0*uScale);
    float angle=random(cell+uSeed)*TAU;
    float glint=pow(max(0.0,cos(angle+dot(uLight,vec2(.9,.6))*5.0)),32.0);
    sparkle=(film(random(cell+7.0))+.25)*glint*.22*(.2+.8*near);
  }
  float reliefHeight=.5;
  if(uTexture>.5 && uTexture<1.5) {
    reliefHeight=ridge((p.x+p.y)*90.0*uScale);
  }
  if(uTexture>1.5 && uTexture<2.5) {
    reliefHeight=ridge(length(p-vec2(.1,-.15))*100.0*uScale);
  }
  if(uTexture>2.5) {
    reliefHeight=ridge(p.x*40.0*uScale)*ridge(p.y*40.0*uScale);
  }
  if(uHasFoil>.5) {
    vec4 f=texture(uFoil,uv);
    reliefHeight=mix(.5,luma(f.rgb/max(f.a,.001)),f.a);
  }
  float relief=(reliefHeight-.5)*.12*uTextureStrength*near;
  color=clamp(color+relief,0.0,1.0);
  float k=clamp(uIntensity,0.0,2.0)*coverage*uActivity*protection;
  if(uPattern>3.5 && uPattern<4.5) k=0.0;
  vec3 result=mix(base,softLight(base,color),clamp(strength*reflection*k,0.0,1.0));
  vec3 reflected=(color*1.3+.15)*streak*(.2+.8*near)*.28+sparkle;
  result+= (1.0-result)*reflected*k;
  result=mix(result,metalColor,clamp(metalCoverage*k,0.0,1.0));
  result=mix(base,clamp(result,0.0,1.0),uOpacity);

  // Lamination remains separate from the foil mask, while respecting the
  // contrast protection of ink already baked into the same source image.
  float gloss=(near*.07+highlight*.12)*uGlare*uActivity*protection;
  result+=(1.0-result)*clamp(gloss,0.0,.65);
  fragColor=vec4(clamp(result,0.0,1.0)*art.a,art.a);
}
