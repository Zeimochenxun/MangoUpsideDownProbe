
; IMAGE 02-mangoUIKit.dylib UNSLID FUNCTION 0xe0f8
0000e0f8  7f2303d5  pacibsp                                                 
0000e0fc  ff4301d1  sub       sp, sp, #0x50                                 
0000e100  f85f01a9  stp       x24, x23, [sp, #0x10]                         
0000e104  f65702a9  stp       x22, x21, [sp, #0x20]                         
0000e108  f44f03a9  stp       x20, x19, [sp, #0x30]                         
0000e10c  fd7b04a9  stp       x29, x30, [sp, #0x40]                         
0000e110  fd030191  add       x29, sp, #0x40                                
0000e114  203f0510  adr       x0, #0x188f8                                   ; CFSTR 'MangoUIKit.Enabled'
0000e118  1f2003d5  nop                                                     
0000e11c  e13f0510  adr       x1, #0x18918                                   ; CFSTR 'com.go.mangoosprefs'
0000e120  1f2003d5  nop                                                     
0000e124  fb160094  bl        #0x13d10                                       ; _CFPreferencesCopyAppValue
0000e128  f30300aa  mov       x19, x0                                       
0000e12c  1f2003d5  nop                                                     
0000e130  c0450758  ldr       x0, #0x1c9e8                                   ; _OBJC_CLASS_$_NSNumber
0000e134  cb170094  bl        #0x14060                                       ; _objc_opt_class
0000e138  e10300aa  mov       x1, x0                                        
0000e13c  e00313aa  mov       x0, x19                                       
0000e140  cc170094  bl        #0x14070                                       ; _objc_opt_isKindOfClass
0000e144  00010037  tbnz      w0, #0, #0xe164                               
0000e148  1f2003d5  nop                                                     
0000e14c  20450758  ldr       x0, #0x1c9f0                                   ; _OBJC_CLASS_$_NSString
0000e150  c4170094  bl        #0x14060                                       ; _objc_opt_class
0000e154  e10300aa  mov       x1, x0                                        
0000e158  e00313aa  mov       x0, x19                                       
0000e15c  c5170094  bl        #0x14070                                       ; _objc_opt_isKindOfClass
0000e160  00010036  tbz       w0, #0, #0xe180                               
0000e164  e00313aa  mov       x0, x19                                       
0000e168  fe180094  bl        #0x14560                                       ; objc_msgSend$boolValue
0000e16c  f40300aa  mov       x20, x0                                       
0000e170  e00313aa  mov       x0, x19                                       
0000e174  cb170094  bl        #0x140a0                                       ; _objc_release
0000e178  94000035  cbnz      w20, #0xe188                                  
0000e17c  23010014  b         #0xe608                                        ; sub_0xe608
0000e180  e00313aa  mov       x0, x19                                       
0000e184  c7170094  bl        #0x140a0                                       ; _objc_release
0000e188  52170094  bl        #0x13ed0                                       ; _getprogname
0000e18c  e02300b4  cbz       x0, #0xe608                                   
0000e190  f40300aa  mov       x20, x0                                       
0000e194  e1100410  adr       x1, #0x163b0                                   ; STR 'backboardd'
0000e198  1f2003d5  nop                                                     
0000e19c  31180094  bl        #0x14260                                       ; _strcmp
0000e1a0  c0000034  cbz       w0, #0xe1b8                                   
0000e1a4  a1100470  adr       x1, #0x163bb                                   ; STR 'SpringBoard'
0000e1a8  1f2003d5  nop                                                     
0000e1ac  e00314aa  mov       x0, x20                                       
0000e1b0  2c180094  bl        #0x14260                                       ; _strcmp
0000e1b4  a0220035  cbnz      w0, #0xe608                                   
0000e1b8  1f2003d5  nop                                                     
0000e1bc  e0410758  ldr       x0, #0x1c9f8                                   ; _OBJC_CLASS_$_NSUserDefaults
0000e1c0  581c0094  bl        #0x15320                                       ; objc_msgSend$standardUserDefaults
0000e1c4  fd031daa  mov       x29, x29                                      
0000e1c8  c2170094  bl        #0x140d0                                       ; _objc_retainAutoreleasedReturnValue
0000e1cc  f30300aa  mov       x19, x0                                       
0000e1d0  423c0510  adr       x2, #0x18958                                   ; CFSTR 'com.mango.unseen'
0000e1d4  1f2003d5  nop                                                     
0000e1d8  ea1a0094  bl        #0x14d80                                       ; objc_msgSend$persistentDomainForName:
0000e1dc  fd031daa  mov       x29, x29                                      
0000e1e0  bc170094  bl        #0x140d0                                       ; _objc_retainAutoreleasedReturnValue
0000e1e4  f50300aa  mov       x21, x0                                       
0000e1e8  e00313aa  mov       x0, x19                                       
0000e1ec  ad170094  bl        #0x140a0                                       ; _objc_release
0000e1f0  350100b5  cbnz      x21, #0xe214                                  
0000e1f4  1f2003d5  nop                                                     
0000e1f8  00410758  ldr       x0, #0x1ca18                                   ; _OBJC_CLASS_$_NSDictionary
0000e1fc  e23f0510  adr       x2, #0x189f8                                   ; CFSTR '/var/mobile/Library/Preferences/com.mango.unseen.plist'
0000e200  1f2003d5  nop                                                     
0000e204  87190094  bl        #0x14820                                       ; objc_msgSend$dictionaryWithContentsOfFile:
0000e208  fd031daa  mov       x29, x29                                      
0000e20c  b1170094  bl        #0x140d0                                       ; _objc_retainAutoreleasedReturnValue
0000e210  f50300aa  mov       x21, x0                                       
0000e214  e00315aa  mov       x0, x21                                       
0000e218  a6170094  bl        #0x140b0                                       ; _objc_retain
0000e21c  f30300aa  mov       x19, x0                                       
0000e220  a0170094  bl        #0x140a0                                       ; _objc_release
0000e224  a13a0510  adr       x1, #0x18978                                   ; CFSTR 'Enabled'
0000e228  1f2003d5  nop                                                     
0000e22c  e00313aa  mov       x0, x19                                       
0000e230  05010094  bl        #0xe644                                        ; sub_0xe644
0000e234  f60000d0  adrp      x22, #0x2c000                                 
0000e238  c0c23939  strb      w0, [x22, #0xe70]                             
0000e23c  e13a0510  adr       x1, #0x18998                                   ; CFSTR 'DisableUpdateMaskPatchEnabled'
0000e240  1f2003d5  nop                                                     
0000e244  e00313aa  mov       x0, x19                                       
0000e248  ff000094  bl        #0xe644                                        ; sub_0xe644
0000e24c  f70000d0  adrp      x23, #0x2c000                                 
0000e250  e0c63939  strb      w0, [x23, #0xe71]                             
0000e254  213b0510  adr       x1, #0x189b8                                   ; CFSTR 'ScreenshotActionFilterEnabled'
0000e258  1f2003d5  nop                                                     
0000e25c  e00313aa  mov       x0, x19                                       
0000e260  f9000094  bl        #0xe644                                        ; sub_0xe644
0000e264  f80000d0  adrp      x24, #0x2c000                                 
0000e268  00cb3939  strb      w0, [x24, #0xe72]                             
0000e26c  613b0510  adr       x1, #0x189d8                                   ; CFSTR 'CaptureStateMaskEnabled'
0000e270  1f2003d5  nop                                                     
0000e274  e00313aa  mov       x0, x19                                       
0000e278  f3000094  bl        #0xe644                                        ; sub_0xe644
0000e27c  f50000d0  adrp      x21, #0x2c000                                 
0000e280  a0ce3939  strb      w0, [x21, #0xe73]                             
0000e284  e00313aa  mov       x0, x19                                       
0000e288  86170094  bl        #0x140a0                                       ; _objc_release
0000e28c  c8c27939  ldrb      w8, [x22, #0xe70]                             
0000e290  c81b0034  cbz       w8, #0xe608                                   
0000e294  21090470  adr       x1, #0x163bb                                   ; STR 'SpringBoard'
0000e298  1f2003d5  nop                                                     
0000e29c  e00314aa  mov       x0, x20                                       
0000e2a0  f0170094  bl        #0x14260                                       ; _strcmp
0000e2a4  e00c0034  cbz       w0, #0xe440                                   
0000e2a8  e8c67939  ldrb      w8, [x23, #0xe71]                             
0000e2ac  48110034  cbz       w8, #0xe4d4                                   
0000e2b0  080080d2  mov       x8, #0                                        
0000e2b4  37008052  mov       w23, #1                                       
0000e2b8  96120510  adr       x22, #0x18508                                  ; PTR STR '__ZN2CA6Render7Updater14prepare_layer0ERNS1_11GlobalStateEPNS0_9LayerNodeEPNS0_5LayerERNS1_11LocalState0Ey'
0000e2bc  1f2003d5  nop                                                     
0000e2c0  b4100470  adr       x20, #0x164d7                                  ; STR '/System/Library/Frameworks/QuartzCore.framework/QuartzCore'
0000e2c4  1f2003d5  nop                                                     
0000e2c8  c17a68f8  ldr       x1, [x22, x8, lsl #3]                          ; PTR STR '__ZN2CA6Render7Updater14prepare_layer0ERNS1_11GlobalStateEPNS0_9LayerNodeEPNS0_5LayerERNS1_11LocalState0Ey'
0000e2cc  e00314aa  mov       x0, x20                                       
0000e2d0  81f9ff97  bl        #0xc8d4                                        ; sub_0xc8d4
0000e2d4  f30300aa  mov       x19, x0                                       
0000e2d8  97000036  tbz       w23, #0, #0xe2e8                              
0000e2dc  17008052  mov       w23, #0                                       
0000e2e0  28008052  mov       w8, #1                                        
0000e2e4  33ffffb4  cbz       x19, #0xe2c8                                  
0000e2e8  730f00b4  cbz       x19, #0xe4d4                                  
0000e2ec  080080d2  mov       x8, #0                                        
0000e2f0  e9838252  mov       w9, #0x141f                                   
0000e2f4  894dbe72  movk      w9, #0xf26c, lsl #16                          
0000e2f8  ea838352  mov       w10, #0x1c1f                                  
0000e2fc  8a4dbe72  movk      w10, #0xf26c, lsl #16                         
0000e300  eb038352  mov       w11, #0x181f                                  
0000e304  8b4dbe72  movk      w11, #0xf26c, lsl #16                         
0000e308  2c008052  mov       w12, #1                                       
0000e30c  0c80aa72  movk      w12, #0x5400, lsl #16                         
0000e310  8dff8752  mov       w13, #0x3ffc                                  
0000e314  ee0313aa  mov       x14, x19                                      
0000e318  6f7a68b8  ldr       w15, [x19, x8, lsl #2]                        
0000e31c  ef691612  and       w15, w15, #0xfffffc1f                         
0000e320  ff01096b  cmp       w15, w9                                       
0000e324  e4114a7a  ccmp      w15, w10, #4, ne                              
0000e328  e4114b7a  ccmp      w15, w11, #4, ne                              
0000e32c  21010054  b.ne      #0xe350                                       
0000e330  2f008052  mov       w15, #1                                       
0000e334  d0796fb8  ldr       w16, [x14, x15, lsl #2]                       
0000e338  10320812  and       w16, w16, #0xff00001f                         
0000e33c  1f020c6b  cmp       w16, w12                                      
0000e340  a00b0054  b.eq      #0xe4b4                                       
0000e344  ef050091  add       x15, x15, #1                                  
0000e348  ff1500f1  cmp       x15, #5                                       
0000e34c  41ffff54  b.ne      #0xe334                                       
0000e350  08050091  add       x8, x8, #1                                    
0000e354  ce110091  add       x14, x14, #4                                  
0000e358  1f010deb  cmp       x8, x13                                       
0000e35c  e1fdff54  b.ne      #0xe318                                       
0000e360  a00b0470  adr       x0, #0x164d7                                   ; STR '/System/Library/Frameworks/QuartzCore.framework/QuartzCore'
0000e364  1f2003d5  nop                                                     
0000e368  01140430  adr       x1, #0x165e9                                   ; STR '__ZN2CA6Render6Update17allowed_in_updateEPNS0_7ContextEPKNS0_5LayerE'
0000e36c  1f2003d5  nop                                                     
0000e370  59f9ff97  bl        #0xc8d4                                        ; sub_0xc8d4
0000e374  000b00b4  cbz       x0, #0xe4d4                                   
0000e378  080080d2  mov       x8, #0                                        
0000e37c  69220091  add       x9, x19, #8                                   
0000e380  0a008092  mov       x10, #-1                                      
0000e384  0be0a652  mov       w11, #0x37000000                              
0000e388  ec038052  mov       w12, #0x1f                                    
0000e38c  0c20bf72  movk      w12, #0xf900, lsl #16                         
0000e390  0dff8752  mov       w13, #0x3ff8                                  
0000e394  6e0a088b  add       x14, x19, x8, lsl #2                          
0000e398  cf0140b9  ldr       w15, [x14]                                    
0000e39c  f07d1a53  lsr       w16, w15, #0x1a                               
0000e3a0  1f960071  cmp       w16, #0x25                                    
0000e3a4  a1000054  b.ne      #0xe3b8                                       
0000e3a8  f0651913  sbfx      w16, w15, #0x19, #1                           
0000e3ac  f0650033  bfxil     w16, w15, #0, #0x1a                           
0000e3b0  cec9308b  add       x14, x14, w16, sxtw #2                        
0000e3b4  02000014  b         #0xe3bc                                        ; sub_0xe3bc
0000e3b8  0e0080d2  mov       x14, #0                                       
0000e3bc  df0100eb  cmp       x14, x0                                       
0000e3c0  e0000054  b.eq      #0xe3dc                                       
0000e3c4  08050091  add       x8, x8, #1                                    
0000e3c8  4a0500d1  sub       x10, x10, #1                                  
0000e3cc  29110091  add       x9, x9, #4                                    
0000e3d0  1f010deb  cmp       x8, x13                                       
0000e3d4  01feff54  b.ne      #0xe394                                       
0000e3d8  3f000014  b         #0xe4d4                                        ; sub_0xe4d4
0000e3dc  ef0309aa  mov       x15, x9                                       
0000e3e0  ee030aaa  mov       x14, x10                                      
0000e3e4  90008052  mov       w16, #4                                       
0000e3e8  31008052  mov       w17, #1                                       
0000e3ec  2102088b  add       x1, x17, x8                                   
0000e3f0  617a61b8  ldr       w1, [x19, x1, lsl #2]                         
0000e3f4  21440d12  and       w1, w1, #0xfff8001f                           
0000e3f8  3f000b6b  cmp       w1, w11                                       
0000e3fc  41010054  b.ne      #0xe424                                       
0000e400  010080d2  mov       x1, #0                                        
0000e404  3f0c00f1  cmp       x1, #3                                        
0000e408  e0000054  b.eq      #0xe424                                       
0000e40c  e27961b8  ldr       w2, [x15, x1, lsl #2]                         
0000e410  42380a12  and       w2, w2, #0xffc0001f                           
0000e414  21040091  add       x1, x1, #1                                    
0000e418  5f000c6b  cmp       w2, w12                                       
0000e41c  41ffff54  b.ne      #0xe404                                       
0000e420  80000014  b         #0xe620                                        ; sub_0xe620
0000e424  31060091  add       x17, x17, #1                                  
0000e428  10060091  add       x16, x16, #1                                  
0000e42c  ce0500d1  sub       x14, x14, #1                                  
0000e430  ef110091  add       x15, x15, #4                                  
0000e434  1f2200f1  cmp       x16, #8                                       
0000e438  a1fdff54  b.ne      #0xe3ec                                       
0000e43c  e2ffff17  b         #0xe3c4                                        ; sub_0xe3c4
0000e440  08cb7939  ldrb      w8, [x24, #0xe72]                             
0000e444  280e0034  cbz       w8, #0xe608                                   
0000e448  80000450  adr       x0, #0x1645a                                   ; STR 'FBScene'
0000e44c  1f2003d5  nop                                                     
0000e450  f0160094  bl        #0x14010                                       ; _objc_getClass
0000e454  a00d00b4  cbz       x0, #0xe608                                   
0000e458  f30300aa  mov       x19, x0                                       
0000e45c  20000450  adr       x0, #0x16462                                   ; STR 'sendActions:'
0000e460  1f2003d5  nop                                                     
0000e464  6f170094  bl        #0x14220                                       ; _sel_registerName
0000e468  000d00b4  cbz       x0, #0xe608                                   
0000e46c  e10300aa  mov       x1, x0                                        
0000e470  83440710  adr       x3, #0x1cd00                                  
0000e474  1f2003d5  nop                                                     
0000e478  50130010  adr       x16, #0xe6e0                                  
0000e47c  1f2003d5  nop                                                     
0000e480  f023c1da  paciza    x16                                           
0000e484  e20310aa  mov       x2, x16                                       
0000e488  e00313aa  mov       x0, x19                                       
0000e48c  fd7b44a9  ldp       x29, x30, [sp, #0x40]                         
0000e490  f44f43a9  ldp       x20, x19, [sp, #0x30]                         
0000e494  f65742a9  ldp       x22, x21, [sp, #0x20]                         
0000e498  f85f41a9  ldp       x24, x23, [sp, #0x10]                         
0000e49c  ff430191  add       sp, sp, #0x50                                 
0000e4a0  ff2303d5  autibsp                                                 
0000e4a4  d0071eca  eor       x16, x30, x30, lsl #1                         
0000e4a8  5000f0b6  tbz       x16, #0x3e, #0xe4b0                           
0000e4ac  208e38d4  brk       #0xc471                                       
0000e4b0  28160014  b         #0x13d50                                       ; _MSHookMessageEx
0000e4b4  08010f8b  add       x8, x8, x15                                   
0000e4b8  600a088b  add       x0, x19, x8, lsl #2                           
0000e4bc  e8038452  mov       w8, #0x201f                                   
0000e4c0  68a0ba72  movk      w8, #0xd503, lsl #16                          
0000e4c4  e80f00b9  str       w8, [sp, #0xc]                                
0000e4c8  e1330091  add       x1, sp, #0xc                                  
0000e4cc  82008052  mov       w2, #4                                        
0000e4d0  3bf4ff97  bl        #0xb5bc                                        ; sub_0xb5bc
0000e4d4  a8ce7939  ldrb      w8, [x21, #0xe73]                             
0000e4d8  88090034  cbz       w8, #0xe608                                   
0000e4dc  c0ff0370  adr       x0, #0x164d7                                   ; STR '/System/Library/Frameworks/QuartzCore.framework/QuartzCore'
0000e4e0  1f2003d5  nop                                                     
0000e4e4  410a0450  adr       x1, #0x1662e                                   ; STR '__ZN2CA12WindowServer6Server16get_display_infoEPNS_6Render6ObjectEPvS5_'
0000e4e8  1f2003d5  nop                                                     
0000e4ec  faf8ff97  bl        #0xc8d4                                        ; sub_0xc8d4
0000e4f0  800800b4  cbz       x0, #0xe600                                   
0000e4f4  080080d2  mov       x8, #0                                        
0000e4f8  0920b752  mov       w9, #-0x47000000                              
0000e4fc  0a200091  add       x10, x0, #8                                   
0000e500  0b7868b8  ldr       w11, [x0, x8, lsl #2]                         
0000e504  6c250a12  and       w12, w11, #0xffc00000                         
0000e508  2d015011  add       w13, w9, #0x400, lsl #12                      
0000e50c  08050091  add       x8, x8, #1                                    
0000e510  9f010d6b  cmp       w12, w13                                      
0000e514  01010054  b.ne      #0xe534                                       
0000e518  0c7868b8  ldr       w12, [x0, x8, lsl #2]                         
0000e51c  8d250a12  and       w13, w12, #0xffc00000                         
0000e520  bf01096b  cmp       w13, w9                                       
0000e524  8d010b4a  eor       w13, w12, w11                                 
0000e528  ad110012  and       w13, w13, #0x1f                               
0000e52c  a009407a  ccmp      w13, #0, #0, eq                               
0000e530  a0000054  b.eq      #0xe544                                       
0000e534  4a110091  add       x10, x10, #4                                  
0000e538  1fe907f1  cmp       x8, #0x1fa                                    
0000e53c  21feff54  b.ne      #0xe500                                       
0000e540  30000014  b         #0xe600                                        ; sub_0xe600
0000e544  0d0080d2  mov       x13, #0                                       
0000e548  6e7d0853  lsr       w14, w11, #8                                  
0000e54c  ce2d1e12  and       w14, w14, #0x3ffc                             
0000e550  ce110011  add       w14, w14, #4                                  
0000e554  4f696db8  ldr       w15, [x10, x13]                               
0000e558  f07d1853  lsr       w16, w15, #0x18                               
0000e55c  1f460271  cmp       w16, #0x91                                    
0000e560  f05d1653  ubfx      w16, w15, #0x16, #2                           
0000e564  020a417a  ccmp      w16, #1, #2, eq                               
0000e568  f1010b4a  eor       w17, w15, w11                                 
0000e56c  31121b12  and       w17, w17, #0x3e0                              
0000e570  209a407a  ccmp      w17, #0, #0, ls                               
0000e574  a0000054  b.eq      #0xe588                                       
0000e578  ad110091  add       x13, x13, #4                                  
0000e57c  bf4100f1  cmp       x13, #0x10                                    
0000e580  a1feff54  b.ne      #0xe554                                       
0000e584  ecffff17  b         #0xe534                                        ; sub_0xe534
0000e588  ef550a53  ubfx      w15, w15, #0xa, #0xc                          
0000e58c  f14d1453  lsl       w17, w15, #0xc                                
0000e590  1f060071  cmp       w16, #1                                       
0000e594  2f028f1a  csel      w15, w17, w15, eq                             
0000e598  ff010e6b  cmp       w15, w14                                      
0000e59c  e1feff54  b.ne      #0xe578                                       
0000e5a0  887d0853  lsr       w8, w12, #8                                   
0000e5a4  e90000d0  adrp      x9, #0x2c000                                  
0000e5a8  082d1e72  ands      w8, w8, #0x3ffc                               
0000e5ac  28910db9  str       w8, [x9, #0xd90]                              
0000e5b0  c0020054  b.eq      #0xe608                                       
0000e5b4  00060450  adr       x0, #0x16676                                   ; STR '__XGetDisplayInfo'
0000e5b8  1f2003d5  nop                                                     
0000e5bc  e23e0f10  adr       x2, #0x2cd98                                  
0000e5c0  1f2003d5  nop                                                     
0000e5c4  70620010  adr       x16, #0xf210                                  
0000e5c8  1f2003d5  nop                                                     
0000e5cc  f023c1da  paciza    x16                                           
0000e5d0  e10310aa  mov       x1, x16                                       
0000e5d4  f8020094  bl        #0xf1b4                                        ; sub_0xf1b4
0000e5d8  a0020450  adr       x0, #0x1662e                                   ; STR '__ZN2CA12WindowServer6Server16get_display_infoEPNS_6Render6ObjectEPvS5_'
0000e5dc  1f2003d5  nop                                                     
0000e5e0  023e0f10  adr       x2, #0x2cda0                                  
0000e5e4  1f2003d5  nop                                                     
0000e5e8  106d0010  adr       x16, #0xf388                                  
0000e5ec  1f2003d5  nop                                                     
0000e5f0  f023c1da  paciza    x16                                           
0000e5f4  e10310aa  mov       x1, x16                                       
0000e5f8  ef020094  bl        #0xf1b4                                        ; sub_0xf1b4
0000e5fc  03000014  b         #0xe608                                        ; sub_0xe608
0000e600  e80000d0  adrp      x8, #0x2c000                                  
0000e604  1f910db9  str       wzr, [x8, #0xd90]                             
0000e608  fd7b44a9  ldp       x29, x30, [sp, #0x40]                         
0000e60c  f44f43a9  ldp       x20, x19, [sp, #0x30]                         
0000e610  f65742a9  ldp       x22, x21, [sp, #0x20]                         
0000e614  f85f41a9  ldp       x24, x23, [sp, #0x10]                         
0000e618  ff430191  add       sp, sp, #0x50                                 
0000e61c  ff0f5fd6  retab                                                   
0000e620  28000ecb  sub       x8, x1, x14                                   
0000e624  a5ffff17  b         #0xe4b8                                        ; sub_0xe4b8
0000e628  02000014  b         #0xe630                                        ; sub_0xe630
0000e62c  01000014  b         #0xe630                                        ; sub_0xe630
0000e630  f40300aa  mov       x20, x0                                       
0000e634  e00313aa  mov       x0, x19                                       
0000e638  9a160094  bl        #0x140a0                                       ; _objc_release
0000e63c  e00314aa  mov       x0, x20                                       
0000e640  d8150094  bl        #0x13da0                                       ; __Unwind_Resume

; IMAGE 02-mangoUIKit.dylib UNSLID FUNCTION 0xf210
0000f210  7f2303d5  pacibsp                                                 
0000f214  f657bda9  stp       x22, x21, [sp, #-0x30]!                       
0000f218  f44f01a9  stp       x20, x19, [sp, #0x10]                         
0000f21c  fd7b02a9  stp       x29, x30, [sp, #0x20]                         
0000f220  fd830091  add       x29, sp, #0x20                                
0000f224  09028252  mov       w9, #0x1010                                   
0000f228  118c0410  adr       x17, #0x183a8                                  ; ___chkstk_darwin
0000f22c  1f2003d5  nop                                                     
0000f230  300240f9  ldr       x16, [x17]                                     ; ___chkstk_darwin
0000f234  110a3fd7  blraa     x16, x17                                      
0000f238  ff0740d1  sub       sp, sp, #1, lsl #12                           
0000f23c  ff4300d1  sub       sp, sp, #0x10                                 
0000f240  f30301aa  mov       x19, x1                                       
0000f244  f40300aa  mov       x20, x0                                       
0000f248  1f2003d5  nop                                                     
0000f24c  a8890458  ldr       x8, #0x18380                                   ; ___stack_chk_guard
0000f250  080140f9  ldr       x8, [x8]                                      
0000f254  a8831df8  stur      x8, [x29, #-0x28]                             
0000f258  e0230091  add       x0, sp, #8                                    
0000f25c  01008252  mov       w1, #0x1000                                   
0000f260  fc120094  bl        #0x13e50                                       ; _bzero
0000f264  f40100b4  cbz       x20, #0xf2a0                                  
0000f268  880640b9  ldr       w8, [x20, #4]                                 
0000f26c  09008812  mov       w9, #-0x4001                                  
0000f270  0901090b  add       w9, w8, w9                                    
0000f274  0afd8712  mov       w10, #-0x3fe9                                 
0000f278  3f010a6b  cmp       w9, w10                                       
0000f27c  23010054  b.lo      #0xf2a0                                       
0000f280  080d0011  add       w8, w8, #3                                    
0000f284  08757e92  and       x8, x8, #0xfffffffc                           
0000f288  8802088b  add       x8, x20, x8                                   
0000f28c  090140b9  ldr       w9, [x8]                                      
0000f290  89000035  cbnz      w9, #0xf2a0                                   
0000f294  090540b9  ldr       w9, [x8, #4]                                  
0000f298  3fd10071  cmp       w9, #0x34                                     
0000f29c  e2040054  b.hs      #0xf338                                       
0000f2a0  40cc0610  adr       x0, #0x1cc28                                  
0000f2a4  1f2003d5  nop                                                     
0000f2a8  f00a0010  adr       x16, #0xf404                                  
0000f2ac  1f2003d5  nop                                                     
0000f2b0  f023c1da  paciza    x16                                           
0000f2b4  e10310aa  mov       x1, x16                                       
0000f2b8  ce130094  bl        #0x141f0                                       ; _pthread_once
0000f2bc  010080d2  mov       x1, #0                                        
0000f2c0  f50000b0  adrp      x21, #0x2c000                                 
0000f2c4  a0d646f9  ldr       x0, [x21, #0xda8]                             
0000f2c8  d2130094  bl        #0x14210                                       ; _pthread_setspecific
0000f2cc  1f2003d5  nop                                                     
0000f2d0  48d60e58  ldr       x8, #0x2cd98                                  
0000f2d4  e00314aa  mov       x0, x20                                       
0000f2d8  e10313aa  mov       x1, x19                                       
0000f2dc  1f093fd6  blraaz    x8                                            
0000f2e0  40ca0610  adr       x0, #0x1cc28                                  
0000f2e4  1f2003d5  nop                                                     
0000f2e8  f0080010  adr       x16, #0xf404                                  
0000f2ec  1f2003d5  nop                                                     
0000f2f0  f023c1da  paciza    x16                                           
0000f2f4  e10310aa  mov       x1, x16                                       
0000f2f8  be130094  bl        #0x141f0                                       ; _pthread_once
0000f2fc  a0d646f9  ldr       x0, [x21, #0xda8]                             
0000f300  010080d2  mov       x1, #0                                        
0000f304  c3130094  bl        #0x14210                                       ; _pthread_setspecific
0000f308  a8835df8  ldur      x8, [x29, #-0x28]                             
0000f30c  1f2003d5  nop                                                     
0000f310  89830458  ldr       x9, #0x18380                                   ; ___stack_chk_guard
0000f314  290140f9  ldr       x9, [x9]                                      
0000f318  3f0108eb  cmp       x9, x8                                        
0000f31c  41030054  b.ne      #0xf384                                       
0000f320  ff074091  add       sp, sp, #1, lsl #12                           
0000f324  ff430091  add       sp, sp, #0x10                                 
0000f328  fd7b42a9  ldp       x29, x30, [sp, #0x20]                         
0000f32c  f44f41a9  ldp       x20, x19, [sp, #0x10]                         
0000f330  f657c3a8  ldp       x22, x21, [sp], #0x30                         
0000f334  ff0f5fd6  retab                                                   
0000f338  002940b9  ldr       w0, [x8, #0x28]                               
0000f33c  1f040071  cmp       w0, #1                                        
0000f340  0bfbff54  b.lt      #0xf2a0                                       
0000f344  081940b9  ldr       w8, [x8, #0x18]                               
0000f348  1fd50771  cmp       w8, #0x1f5                                    
0000f34c  a1faff54  b.ne      #0xf2a0                                       
0000f350  e2230091  add       x2, sp, #8                                    
0000f354  21008052  mov       w1, #1                                        
0000f358  0fffff97  bl        #0xef94                                        ; sub_0xef94
0000f35c  f50300aa  mov       x21, x0                                       
0000f360  40c60610  adr       x0, #0x1cc28                                  
0000f364  1f2003d5  nop                                                     
0000f368  f0040010  adr       x16, #0xf404                                  
0000f36c  1f2003d5  nop                                                     
0000f370  f023c1da  paciza    x16                                           
0000f374  e10310aa  mov       x1, x16                                       
0000f378  9e130094  bl        #0x141f0                                       ; _pthread_once
0000f37c  e103152a  mov       w1, w21                                       
0000f380  d0ffff17  b         #0xf2c0                                        ; sub_0xf2c0
0000f384  a3120094  bl        #0x13e10                                       ; ___stack_chk_fail

; IMAGE 02-mangoUIKit.dylib UNSLID FUNCTION 0xf388
0000f388  7f2303d5  pacibsp                                                 
0000f38c  f44fbea9  stp       x20, x19, [sp, #-0x20]!                       
0000f390  fd7b01a9  stp       x29, x30, [sp, #0x10]                         
0000f394  fd430091  add       x29, sp, #0x10                                
0000f398  f30302aa  mov       x19, x2                                       
0000f39c  1f2003d5  nop                                                     
0000f3a0  08d00e58  ldr       x8, #0x2cda0                                  
0000f3a4  1f093fd6  blraaz    x8                                            
0000f3a8  f40300aa  mov       x20, x0                                       
0000f3ac  e0c30610  adr       x0, #0x1cc28                                  
0000f3b0  1f2003d5  nop                                                     
0000f3b4  90020010  adr       x16, #0xf404                                  
0000f3b8  1f2003d5  nop                                                     
0000f3bc  f023c1da  paciza    x16                                           
0000f3c0  e10310aa  mov       x1, x16                                       
0000f3c4  8b130094  bl        #0x141f0                                       ; _pthread_once
0000f3c8  1f2003d5  nop                                                     
0000f3cc  e0ce0e58  ldr       x0, #0x2cda8                                  
0000f3d0  78130094  bl        #0x141b0                                       ; _pthread_getspecific
0000f3d4  130100b4  cbz       x19, #0xf3f4                                  
0000f3d8  e00000b4  cbz       x0, #0xf3f4                                   
0000f3dc  1f2003d5  nop                                                     
0000f3e0  88cd0e18  ldr       w8, #0x2cd90                                  
0000f3e4  88000034  cbz       w8, #0xf3f4                                   
0000f3e8  696a68b8  ldr       w9, [x19, x8]                                 
0000f3ec  29791d12  and       w9, w9, #0xfffffffb                           
0000f3f0  696a28b8  str       w9, [x19, x8]                                 
0000f3f4  e00314aa  mov       x0, x20                                       
0000f3f8  fd7b41a9  ldp       x29, x30, [sp, #0x10]                         
0000f3fc  f44fc2a8  ldp       x20, x19, [sp], #0x20                         
0000f400  ff0f5fd6  retab                                                   
