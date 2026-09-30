float dispersion=clamp(u.dispersionStrength,0.0,20.0);
if(miaIsIslandMarker(u.tintColor)){
 float4 c=src.sample(s,backdropSampleUV(capturePx,px,dispPx,isCoverSheet,u));
 if(c.a<.01)c=src.sample(s,captureUV);
 dispersion=clamp(dispersion*mix(1.0,1.60,miaHighlightAmount(c.rgb,u.tintColor)),0.0,20.0);
}                   