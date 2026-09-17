
0x4000
00004000  7f2303d5  pacibsp                                                 
00004004  ff0302d1  sub       sp, sp, #0x80                                 
00004008  fd7b07a9  stp       x29, x30, [sp, #0x70]                         
0000400c  fdc30191  add       x29, sp, #0x70                                
00004010  10000090  adrp      x16, #0x4000                                  
00004014  10d20691  add       x16, x16, #0x1b4                               ; __ZL52_logos_method$_ungrouped$UIDevice$userInterfaceIdiomP8UIDeviceP13objc_selector
00004018  f023c1da  paciza    x16                                           
0000401c  f00300f9  str       x16, [sp]                                     
00004020  10000090  adrp      x16, #0x4000                                  
00004024  10720891  add       x16, x16, #0x21c                               ; __ZL92_logos_method$_ungrouped$SBTraitsSceneParticipantDelegate$_isAllowedToHavePortraitUpsideDownP32SBTraitsSceneParticipantDelegateP13objc_selector
00004028  f023c1da  paciza    x16                                           
0000402c  f00700f9  str       x16, [sp, #8]                                 
00004030  10000090  adrp      x16, #0x4000                                  
00004034  10e20891  add       x16, x16, #0x238                               ; __ZL74_logos_method$_ungrouped$SBTraitsSceneParticipantDelegate$_orientationModeP32SBTraitsSceneParticipantDelegateP13objc_selector
00004038  f023c1da  paciza    x16                                           
0000403c  f00b00f9  str       x16, [sp, #0x10]                              
00004040  10000090  adrp      x16, #0x4000                                  
00004044  10820a91  add       x16, x16, #0x2a0                               ; __ZL60_logos_method$_ungrouped$SpringBoard$homeScreenRotationStyleP11SpringBoardP13objc_selector
00004048  f023c1da  paciza    x16                                           
0000404c  f00f00f9  str       x16, [sp, #0x18]                              
00004050  10000090  adrp      x16, #0x4000                                  
00004054  10e20a91  add       x16, x16, #0x2b8                               ; __ZL54_logos_method$_ungrouped$SBApplication$isMedusaCapableP13SBApplicationP13objc_selector
00004058  f023c1da  paciza    x16                                           
0000405c  f01300f9  str       x16, [sp, #0x20]                              
00004060  10000090  adrp      x16, #0x4000                                  
00004064  10520b91  add       x16, x16, #0x2d4                               ; __ZL82_logos_method$_ungrouped$SBHomeScreenViewController$supportedInterfaceOrientationsP26SBHomeScreenViewControllerP13objc_selector
00004068  f023c1da  paciza    x16                                           
0000406c  f01700f9  str       x16, [sp, #0x28]                              
00004070  10000090  adrp      x16, #0x4000                                  
00004074  10420c91  add       x16, x16, #0x310                               ; __ZL96_logos_method$_ungrouped$SBCoverSheetPrimarySlidingViewController$supportedInterfaceOrientationsP40SBCoverSheetPrimarySlidingViewControllerP13objc_selector
00004078  f023c1da  paciza    x16                                           
0000407c  f01f00f9  str       x16, [sp, #0x38]                              
00004080  00000090  adrp      x0, #0x4000                                   
00004084  00c00d91  add       x0, x0, #0x370                                 ; STR 'UIDevice'
00004088  b1000094  bl        #0x434c                                        ; _objc_getClass
0000408c  e20340f9  ldr       x2, [sp]                                      
00004090  a0831ff8  stur      x0, [x29, #-8]                                
00004094  a0835ff8  ldur      x0, [x29, #-8]                                
00004098  48000090  adrp      x8, #0xc000                                   
0000409c  010140f9  ldr       x1, [x8]                                       ; SEL userInterfaceIdiom
000040a0  43000090  adrp      x3, #0xc000                                   
000040a4  63c00091  add       x3, x3, #0x30                                  ; __ZL50_logos_orig$_ungrouped$UIDevice$userInterfaceIdiom
000040a8  ad000094  bl        #0x435c                                        ; _MSHookMessageEx
000040ac  00000090  adrp      x0, #0x4000                                   
000040b0  00e40d91  add       x0, x0, #0x379                                 ; STR 'SBTraitsSceneParticipantDelegate'
000040b4  a6000094  bl        #0x434c                                        ; _objc_getClass
000040b8  e20740f9  ldr       x2, [sp, #8]                                  
000040bc  a0031ff8  stur      x0, [x29, #-0x10]                             
000040c0  a0035ff8  ldur      x0, [x29, #-0x10]                             
000040c4  48000090  adrp      x8, #0xc000                                   
000040c8  010540f9  ldr       x1, [x8, #8]                                   ; SEL _isAllowedToHavePortraitUpsideDown
000040cc  43000090  adrp      x3, #0xc000                                   
000040d0  63e00091  add       x3, x3, #0x38                                  ; __ZL90_logos_orig$_ungrouped$SBTraitsSceneParticipantDelegate$_isAllowedToHavePortraitUpsideDown
000040d4  a2000094  bl        #0x435c                                        ; _MSHookMessageEx
000040d8  e20b40f9  ldr       x2, [sp, #0x10]                               
000040dc  a0035ff8  ldur      x0, [x29, #-0x10]                             
000040e0  48000090  adrp      x8, #0xc000                                   
000040e4  010940f9  ldr       x1, [x8, #0x10]                                ; SEL _orientationMode
000040e8  43000090  adrp      x3, #0xc000                                   
000040ec  63000191  add       x3, x3, #0x40                                  ; __ZL72_logos_orig$_ungrouped$SBTraitsSceneParticipantDelegate$_orientationMode
000040f0  9b000094  bl        #0x435c                                        ; _MSHookMessageEx
000040f4  00000090  adrp      x0, #0x4000                                   
000040f8  00680e91  add       x0, x0, #0x39a                                 ; STR 'SpringBoard'
000040fc  94000094  bl        #0x434c                                        ; _objc_getClass
00004100  e20f40f9  ldr       x2, [sp, #0x18]                               
00004104  a0831ef8  stur      x0, [x29, #-0x18]                             
00004108  a0835ef8  ldur      x0, [x29, #-0x18]                             
0000410c  48000090  adrp      x8, #0xc000                                   
00004110  010d40f9  ldr       x1, [x8, #0x18]                                ; SEL homeScreenRotationStyle
00004114  43000090  adrp      x3, #0xc000                                   
00004118  63200191  add       x3, x3, #0x48                                  ; __ZL58_logos_orig$_ungrouped$SpringBoard$homeScreenRotationStyle
0000411c  90000094  bl        #0x435c                                        ; _MSHookMessageEx
00004120  00000090  adrp      x0, #0x4000                                   
00004124  00980e91  add       x0, x0, #0x3a6                                 ; STR 'SBApplication'
00004128  89000094  bl        #0x434c                                        ; _objc_getClass
0000412c  e21340f9  ldr       x2, [sp, #0x20]                               
00004130  a0031ef8  stur      x0, [x29, #-0x20]                             
00004134  a0035ef8  ldur      x0, [x29, #-0x20]                             
00004138  48000090  adrp      x8, #0xc000                                   
0000413c  011140f9  ldr       x1, [x8, #0x20]                                ; SEL isMedusaCapable
00004140  43000090  adrp      x3, #0xc000                                   
00004144  63400191  add       x3, x3, #0x50                                  ; __ZL52_logos_orig$_ungrouped$SBApplication$isMedusaCapable
00004148  85000094  bl        #0x435c                                        ; _MSHookMessageEx
0000414c  00000090  adrp      x0, #0x4000                                   
00004150  00d00e91  add       x0, x0, #0x3b4                                 ; STR 'SBHomeScreenViewController'
00004154  7e000094  bl        #0x434c                                        ; _objc_getClass
00004158  e21740f9  ldr       x2, [sp, #0x28]                               
0000415c  a0831df8  stur      x0, [x29, #-0x28]                             
00004160  a0835df8  ldur      x0, [x29, #-0x28]                             
00004164  48000090  adrp      x8, #0xc000                                   
00004168  e81b00f9  str       x8, [sp, #0x30]                               
0000416c  011540f9  ldr       x1, [x8, #0x28]                                ; SEL supportedInterfaceOrientations
00004170  43000090  adrp      x3, #0xc000                                   
00004174  63600191  add       x3, x3, #0x58                                  ; __ZL80_logos_orig$_ungrouped$SBHomeScreenViewController$supportedInterfaceOrientations
00004178  79000094  bl        #0x435c                                        ; _MSHookMessageEx
0000417c  00000090  adrp      x0, #0x4000                                   
00004180  003c0f91  add       x0, x0, #0x3cf                                 ; STR 'SBCoverSheetPrimarySlidingViewController'
00004184  72000094  bl        #0x434c                                        ; _objc_getClass
00004188  e81b40f9  ldr       x8, [sp, #0x30]                               
0000418c  e21f40f9  ldr       x2, [sp, #0x38]                               
00004190  a0031df8  stur      x0, [x29, #-0x30]                             
00004194  a0035df8  ldur      x0, [x29, #-0x30]                             
00004198  011540f9  ldr       x1, [x8, #0x28]                               
0000419c  43000090  adrp      x3, #0xc000                                   
000041a0  63800191  add       x3, x3, #0x60                                  ; __ZL94_logos_orig$_ungrouped$SBCoverSheetPrimarySlidingViewController$supportedInterfaceOrientations
000041a4  6e000094  bl        #0x435c                                        ; _MSHookMessageEx
000041a8  fd7b47a9  ldp       x29, x30, [sp, #0x70]                         
000041ac  ff030291  add       sp, sp, #0x80                                 
000041b0  ff0f5fd6  retab                                                   

__ZL52_logos_method$_ungrouped$UIDevice$userInterfaceIdiomP8UIDeviceP13objc_selector
000041b4  7f2303d5  pacibsp                                                 
000041b8  ffc300d1  sub       sp, sp, #0x30                                 
000041bc  fd7b02a9  stp       x29, x30, [sp, #0x20]                         
000041c0  fd830091  add       x29, sp, #0x20                                
000041c4  e00b00f9  str       x0, [sp, #0x10]                               
000041c8  e10700f9  str       x1, [sp, #8]                                  
000041cc  48000090  adrp      x8, #0xc000                                   
000041d0  08d14079  ldrh      w8, [x8, #0x68]                               
000041d4  08010071  subs      w8, w8, #0                                    
000041d8  e8c79f1a  cset      w8, le                                        
000041dc  a8000037  tbnz      w8, #0, #0x41f0                               
000041e0  01000014  b         #0x41e4                                        ; sub_0x41e4
000041e4  280080d2  mov       x8, #1                                        
000041e8  a8831ff8  stur      x8, [x29, #-8]                                
000041ec  08000014  b         #0x420c                                        ; sub_0x420c
000041f0  48000090  adrp      x8, #0xc000                                   
000041f4  081940f9  ldr       x8, [x8, #0x30]                                ; __ZL50_logos_orig$_ungrouped$UIDevice$userInterfaceIdiom
000041f8  e00b40f9  ldr       x0, [sp, #0x10]                               
000041fc  e10740f9  ldr       x1, [sp, #8]                                  
00004200  1f093fd6  blraaz    x8                                            
00004204  a0831ff8  stur      x0, [x29, #-8]                                
00004208  01000014  b         #0x420c                                        ; sub_0x420c
0000420c  a0835ff8  ldur      x0, [x29, #-8]                                
00004210  fd7b42a9  ldp       x29, x30, [sp, #0x20]                         
00004214  ffc30091  add       sp, sp, #0x30                                 
00004218  ff0f5fd6  retab                                                   

__ZL92_logos_method$_ungrouped$SBTraitsSceneParticipantDelegate$_isAllowedToHavePortraitUpsideDownP32SBTraitsSceneParticipantDelegateP13objc_selector
0000421c  ff4300d1  sub       sp, sp, #0x10                                 
00004220  e00700f9  str       x0, [sp, #8]                                  
00004224  e10300f9  str       x1, [sp]                                      
00004228  28008052  mov       w8, #1                                        
0000422c  00010012  and       w0, w8, #1                                    
00004230  ff430091  add       sp, sp, #0x10                                 
00004234  c0035fd6  ret                                                     

__ZL74_logos_method$_ungrouped$SBTraitsSceneParticipantDelegate$_orientationModeP32SBTraitsSceneParticipantDelegateP13objc_selector
00004238  7f2303d5  pacibsp                                                 
0000423c  ffc300d1  sub       sp, sp, #0x30                                 
00004240  fd7b02a9  stp       x29, x30, [sp, #0x20]                         
00004244  fd830091  add       x29, sp, #0x20                                
00004248  a0831ff8  stur      x0, [x29, #-8]                                
0000424c  e10b00f9  str       x1, [sp, #0x10]                               
00004250  49000090  adrp      x9, #0xc000                                   
00004254  e90300f9  str       x9, [sp]                                      
00004258  28d14079  ldrh      w8, [x9, #0x68]                               
0000425c  08050011  add       w8, w8, #1                                    
00004260  28d10079  strh      w8, [x9, #0x68]                               
00004264  48000090  adrp      x8, #0xc000                                   
00004268  082140f9  ldr       x8, [x8, #0x40]                                ; __ZL72_logos_orig$_ungrouped$SBTraitsSceneParticipantDelegate$_orientationMode
0000426c  a0835ff8  ldur      x0, [x29, #-8]                                
00004270  e10b40f9  ldr       x1, [sp, #0x10]                               
00004274  1f093fd6  blraaz    x8                                            
00004278  e90340f9  ldr       x9, [sp]                                      
0000427c  e00700f9  str       x0, [sp, #8]                                  
00004280  2ad14079  ldrh      w10, [x9, #0x68]                              
00004284  08008012  mov       w8, #-1                                       
00004288  08212a0b  add       w8, w8, w10, uxth                             
0000428c  28d10079  strh      w8, [x9, #0x68]                               
00004290  e00740f9  ldr       x0, [sp, #8]                                  
00004294  fd7b42a9  ldp       x29, x30, [sp, #0x20]                         
00004298  ffc30091  add       sp, sp, #0x30                                 
0000429c  ff0f5fd6  retab                                                   

__ZL60_logos_method$_ungrouped$SpringBoard$homeScreenRotationStyleP11SpringBoardP13objc_selector
000042a0  ff4300d1  sub       sp, sp, #0x10                                 
000042a4  e00700f9  str       x0, [sp, #8]                                  
000042a8  e10300f9  str       x1, [sp]                                      
000042ac  200080d2  mov       x0, #1                                        
000042b0  ff430091  add       sp, sp, #0x10                                 
000042b4  c0035fd6  ret                                                     

__ZL54_logos_method$_ungrouped$SBApplication$isMedusaCapableP13SBApplicationP13objc_selector
000042b8  ff4300d1  sub       sp, sp, #0x10                                 
000042bc  e00700f9  str       x0, [sp, #8]                                  
000042c0  e10300f9  str       x1, [sp]                                      
000042c4  28008052  mov       w8, #1                                        
000042c8  00010012  and       w0, w8, #1                                    
000042cc  ff430091  add       sp, sp, #0x10                                 
000042d0  c0035fd6  ret                                                     

__ZL82_logos_method$_ungrouped$SBHomeScreenViewController$supportedInterfaceOrientationsP26SBHomeScreenViewControllerP13objc_selector
000042d4  7f2303d5  pacibsp                                                 
000042d8  ff8300d1  sub       sp, sp, #0x20                                 
000042dc  fd7b01a9  stp       x29, x30, [sp, #0x10]                         
000042e0  fd430091  add       x29, sp, #0x10                                
000042e4  e00700f9  str       x0, [sp, #8]                                  
000042e8  e10300f9  str       x1, [sp]                                      
000042ec  48000090  adrp      x8, #0xc000                                   
000042f0  082d40f9  ldr       x8, [x8, #0x58]                                ; __ZL80_logos_orig$_ungrouped$SBHomeScreenViewController$supportedInterfaceOrientations
000042f4  e00740f9  ldr       x0, [sp, #8]                                  
000042f8  e10340f9  ldr       x1, [sp]                                      
000042fc  1f093fd6  blraaz    x8                                            
00004300  00007eb2  orr       x0, x0, #4                                    
00004304  fd7b41a9  ldp       x29, x30, [sp, #0x10]                         
00004308  ff830091  add       sp, sp, #0x20                                 
0000430c  ff0f5fd6  retab                                                   

__ZL96_logos_method$_ungrouped$SBCoverSheetPrimarySlidingViewController$supportedInterfaceOrientationsP40SBCoverSheetPrimarySlidingViewControllerP13objc_selector
00004310  7f2303d5  pacibsp                                                 
00004314  ff8300d1  sub       sp, sp, #0x20                                 
00004318  fd7b01a9  stp       x29, x30, [sp, #0x10]                         
0000431c  fd430091  add       x29, sp, #0x10                                
00004320  e00700f9  str       x0, [sp, #8]                                  
00004324  e10300f9  str       x1, [sp]                                      
00004328  48000090  adrp      x8, #0xc000                                   
0000432c  083140f9  ldr       x8, [x8, #0x60]                                ; __ZL94_logos_orig$_ungrouped$SBCoverSheetPrimarySlidingViewController$supportedInterfaceOrientations
00004330  e00740f9  ldr       x0, [sp, #8]                                  
00004334  e10340f9  ldr       x1, [sp]                                      
00004338  1f093fd6  blraaz    x8                                            
0000433c  00007eb2  orr       x0, x0, #4                                    
00004340  fd7b41a9  ldp       x29, x30, [sp, #0x10]                         
00004344  ff830091  add       sp, sp, #0x20                                 
00004348  ff0f5fd6  retab                                                   