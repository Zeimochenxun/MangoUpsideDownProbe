
0x4000
00004000  ff4301d1  sub       sp, sp, #0x50                                 
00004004  fd7b04a9  stp       x29, x30, [sp, #0x40]                         
00004008  fd030191  add       x29, sp, #0x40                                
0000400c  00000090  adrp      x0, #0x4000                                   
00004010  00b00c91  add       x0, x0, #0x32c                                 ; STR 'UIDevice'
00004014  b4000094  bl        #0x42e4                                        ; _objc_getClass
00004018  a0831ff8  stur      x0, [x29, #-8]                                
0000401c  a0835ff8  ldur      x0, [x29, #-8]                                
00004020  28000090  adrp      x8, #0x8000                                   
00004024  011540f9  ldr       x1, [x8, #0x28]                                ; SEL userInterfaceIdiom
00004028  02000090  adrp      x2, #0x4000                                   
0000402c  42700591  add       x2, x2, #0x15c                                 ; __ZL52_logos_method$_ungrouped$UIDevice$userInterfaceIdiomP8UIDeviceP13objc_selector
00004030  23000090  adrp      x3, #0x8000                                   
00004034  63800191  add       x3, x3, #0x60                                  ; __ZL50_logos_orig$_ungrouped$UIDevice$userInterfaceIdiom
00004038  ae000094  bl        #0x42f0                                        ; _MSHookMessageEx
0000403c  00000090  adrp      x0, #0x4000                                   
00004040  00d40c91  add       x0, x0, #0x335                                 ; STR 'SBTraitsSceneParticipantDelegate'
00004044  a8000094  bl        #0x42e4                                        ; _objc_getClass
00004048  a0031ff8  stur      x0, [x29, #-0x10]                             
0000404c  a0035ff8  ldur      x0, [x29, #-0x10]                             
00004050  28000090  adrp      x8, #0x8000                                   
00004054  011940f9  ldr       x1, [x8, #0x30]                                ; SEL _isAllowedToHavePortraitUpsideDown
00004058  02000090  adrp      x2, #0x4000                                   
0000405c  42000791  add       x2, x2, #0x1c0                                 ; __ZL92_logos_method$_ungrouped$SBTraitsSceneParticipantDelegate$_isAllowedToHavePortraitUpsideDownP32SBTraitsSceneParticipantDelegateP13objc_selector
00004060  23000090  adrp      x3, #0x8000                                   
00004064  63a00191  add       x3, x3, #0x68                                  ; __ZL90_logos_orig$_ungrouped$SBTraitsSceneParticipantDelegate$_isAllowedToHavePortraitUpsideDown
00004068  a2000094  bl        #0x42f0                                        ; _MSHookMessageEx
0000406c  a0035ff8  ldur      x0, [x29, #-0x10]                             
00004070  28000090  adrp      x8, #0x8000                                   
00004074  011d40f9  ldr       x1, [x8, #0x38]                                ; SEL _orientationMode
00004078  02000090  adrp      x2, #0x4000                                   
0000407c  42700791  add       x2, x2, #0x1dc                                 ; __ZL74_logos_method$_ungrouped$SBTraitsSceneParticipantDelegate$_orientationModeP32SBTraitsSceneParticipantDelegateP13objc_selector
00004080  23000090  adrp      x3, #0x8000                                   
00004084  63c00191  add       x3, x3, #0x70                                  ; __ZL72_logos_orig$_ungrouped$SBTraitsSceneParticipantDelegate$_orientationMode
00004088  9a000094  bl        #0x42f0                                        ; _MSHookMessageEx
0000408c  00000090  adrp      x0, #0x4000                                   
00004090  00580d91  add       x0, x0, #0x356                                 ; STR 'SpringBoard'
00004094  94000094  bl        #0x42e4                                        ; _objc_getClass
00004098  a0831ef8  stur      x0, [x29, #-0x18]                             
0000409c  a0835ef8  ldur      x0, [x29, #-0x18]                             
000040a0  28000090  adrp      x8, #0x8000                                   
000040a4  012140f9  ldr       x1, [x8, #0x40]                                ; SEL homeScreenRotationStyle
000040a8  02000090  adrp      x2, #0x4000                                   
000040ac  42000991  add       x2, x2, #0x240                                 ; __ZL60_logos_method$_ungrouped$SpringBoard$homeScreenRotationStyleP11SpringBoardP13objc_selector
000040b0  23000090  adrp      x3, #0x8000                                   
000040b4  63e00191  add       x3, x3, #0x78                                  ; __ZL58_logos_orig$_ungrouped$SpringBoard$homeScreenRotationStyle
000040b8  8e000094  bl        #0x42f0                                        ; _MSHookMessageEx
000040bc  00000090  adrp      x0, #0x4000                                   
000040c0  00880d91  add       x0, x0, #0x362                                 ; STR 'SBApplication'
000040c4  88000094  bl        #0x42e4                                        ; _objc_getClass
000040c8  e01300f9  str       x0, [sp, #0x20]                               
000040cc  e01340f9  ldr       x0, [sp, #0x20]                               
000040d0  28000090  adrp      x8, #0x8000                                   
000040d4  012540f9  ldr       x1, [x8, #0x48]                                ; SEL isMedusaCapable
000040d8  02000090  adrp      x2, #0x4000                                   
000040dc  42600991  add       x2, x2, #0x258                                 ; __ZL54_logos_method$_ungrouped$SBApplication$isMedusaCapableP13SBApplicationP13objc_selector
000040e0  23000090  adrp      x3, #0x8000                                   
000040e4  63000291  add       x3, x3, #0x80                                  ; __ZL52_logos_orig$_ungrouped$SBApplication$isMedusaCapable
000040e8  82000094  bl        #0x42f0                                        ; _MSHookMessageEx
000040ec  00000090  adrp      x0, #0x4000                                   
000040f0  00c00d91  add       x0, x0, #0x370                                 ; STR 'SBHomeScreenViewController'
000040f4  7c000094  bl        #0x42e4                                        ; _objc_getClass
000040f8  e00f00f9  str       x0, [sp, #0x18]                               
000040fc  e00f40f9  ldr       x0, [sp, #0x18]                               
00004100  28000090  adrp      x8, #0x8000                                   
00004104  e80700f9  str       x8, [sp, #8]                                  
00004108  012940f9  ldr       x1, [x8, #0x50]                                ; SEL supportedInterfaceOrientations
0000410c  02000090  adrp      x2, #0x4000                                   
00004110  42d00991  add       x2, x2, #0x274                                 ; __ZL82_logos_method$_ungrouped$SBHomeScreenViewController$supportedInterfaceOrientationsP26SBHomeScreenViewControllerP13objc_selector
00004114  23000090  adrp      x3, #0x8000                                   
00004118  63200291  add       x3, x3, #0x88                                  ; __ZL80_logos_orig$_ungrouped$SBHomeScreenViewController$supportedInterfaceOrientations
0000411c  75000094  bl        #0x42f0                                        ; _MSHookMessageEx
00004120  00000090  adrp      x0, #0x4000                                   
00004124  002c0e91  add       x0, x0, #0x38b                                 ; STR 'SBCoverSheetPrimarySlidingViewController'
00004128  6f000094  bl        #0x42e4                                        ; _objc_getClass
0000412c  e80740f9  ldr       x8, [sp, #8]                                  
00004130  e00b00f9  str       x0, [sp, #0x10]                               
00004134  e00b40f9  ldr       x0, [sp, #0x10]                               
00004138  012940f9  ldr       x1, [x8, #0x50]                               
0000413c  02000090  adrp      x2, #0x4000                                   
00004140  42b00a91  add       x2, x2, #0x2ac                                 ; __ZL96_logos_method$_ungrouped$SBCoverSheetPrimarySlidingViewController$supportedInterfaceOrientationsP40SBCoverSheetPrimarySlidingViewControllerP13objc_selector
00004144  23000090  adrp      x3, #0x8000                                   
00004148  63400291  add       x3, x3, #0x90                                  ; __ZL94_logos_orig$_ungrouped$SBCoverSheetPrimarySlidingViewController$supportedInterfaceOrientations
0000414c  69000094  bl        #0x42f0                                        ; _MSHookMessageEx
00004150  fd7b44a9  ldp       x29, x30, [sp, #0x40]                         
00004154  ff430191  add       sp, sp, #0x50                                 
00004158  c0035fd6  ret                                                     

__ZL52_logos_method$_ungrouped$UIDevice$userInterfaceIdiomP8UIDeviceP13objc_selector
0000415c  ffc300d1  sub       sp, sp, #0x30                                 
00004160  fd7b02a9  stp       x29, x30, [sp, #0x20]                         
00004164  fd830091  add       x29, sp, #0x20                                
00004168  e00b00f9  str       x0, [sp, #0x10]                               
0000416c  e10700f9  str       x1, [sp, #8]                                  
00004170  28000090  adrp      x8, #0x8000                                   
00004174  08314179  ldrh      w8, [x8, #0x98]                               
00004178  08010071  subs      w8, w8, #0                                    
0000417c  e8c79f1a  cset      w8, le                                        
00004180  a8000037  tbnz      w8, #0, #0x4194                               
00004184  01000014  b         #0x4188                                        ; sub_0x4188
00004188  280080d2  mov       x8, #1                                        
0000418c  a8831ff8  stur      x8, [x29, #-8]                                
00004190  08000014  b         #0x41b0                                        ; sub_0x41b0
00004194  28000090  adrp      x8, #0x8000                                   
00004198  083140f9  ldr       x8, [x8, #0x60]                                ; __ZL50_logos_orig$_ungrouped$UIDevice$userInterfaceIdiom
0000419c  e00b40f9  ldr       x0, [sp, #0x10]                               
000041a0  e10740f9  ldr       x1, [sp, #8]                                  
000041a4  00013fd6  blr       x8                                            
000041a8  a0831ff8  stur      x0, [x29, #-8]                                
000041ac  01000014  b         #0x41b0                                        ; sub_0x41b0
000041b0  a0835ff8  ldur      x0, [x29, #-8]                                
000041b4  fd7b42a9  ldp       x29, x30, [sp, #0x20]                         
000041b8  ffc30091  add       sp, sp, #0x30                                 
000041bc  c0035fd6  ret                                                     

__ZL92_logos_method$_ungrouped$SBTraitsSceneParticipantDelegate$_isAllowedToHavePortraitUpsideDownP32SBTraitsSceneParticipantDelegateP13objc_selector
000041c0  ff4300d1  sub       sp, sp, #0x10                                 
000041c4  e00700f9  str       x0, [sp, #8]                                  
000041c8  e10300f9  str       x1, [sp]                                      
000041cc  28008052  mov       w8, #1                                        
000041d0  00010012  and       w0, w8, #1                                    
000041d4  ff430091  add       sp, sp, #0x10                                 
000041d8  c0035fd6  ret                                                     

__ZL74_logos_method$_ungrouped$SBTraitsSceneParticipantDelegate$_orientationModeP32SBTraitsSceneParticipantDelegateP13objc_selector
000041dc  ffc300d1  sub       sp, sp, #0x30                                 
000041e0  fd7b02a9  stp       x29, x30, [sp, #0x20]                         
000041e4  fd830091  add       x29, sp, #0x20                                
000041e8  a0831ff8  stur      x0, [x29, #-8]                                
000041ec  e10b00f9  str       x1, [sp, #0x10]                               
000041f0  29000090  adrp      x9, #0x8000                                   
000041f4  e90300f9  str       x9, [sp]                                      
000041f8  28314179  ldrh      w8, [x9, #0x98]                               
000041fc  08050011  add       w8, w8, #1                                    
00004200  28310179  strh      w8, [x9, #0x98]                               
00004204  28000090  adrp      x8, #0x8000                                   
00004208  083940f9  ldr       x8, [x8, #0x70]                                ; __ZL72_logos_orig$_ungrouped$SBTraitsSceneParticipantDelegate$_orientationMode
0000420c  a0835ff8  ldur      x0, [x29, #-8]                                
00004210  e10b40f9  ldr       x1, [sp, #0x10]                               
00004214  00013fd6  blr       x8                                            
00004218  e90340f9  ldr       x9, [sp]                                      
0000421c  e00700f9  str       x0, [sp, #8]                                  
00004220  2a314179  ldrh      w10, [x9, #0x98]                              
00004224  08008012  mov       w8, #-1                                       
00004228  08212a0b  add       w8, w8, w10, uxth                             
0000422c  28310179  strh      w8, [x9, #0x98]                               
00004230  e00740f9  ldr       x0, [sp, #8]                                  
00004234  fd7b42a9  ldp       x29, x30, [sp, #0x20]                         
00004238  ffc30091  add       sp, sp, #0x30                                 
0000423c  c0035fd6  ret                                                     

__ZL60_logos_method$_ungrouped$SpringBoard$homeScreenRotationStyleP11SpringBoardP13objc_selector
00004240  ff4300d1  sub       sp, sp, #0x10                                 
00004244  e00700f9  str       x0, [sp, #8]                                  
00004248  e10300f9  str       x1, [sp]                                      
0000424c  200080d2  mov       x0, #1                                        
00004250  ff430091  add       sp, sp, #0x10                                 
00004254  c0035fd6  ret                                                     

__ZL54_logos_method$_ungrouped$SBApplication$isMedusaCapableP13SBApplicationP13objc_selector
00004258  ff4300d1  sub       sp, sp, #0x10                                 
0000425c  e00700f9  str       x0, [sp, #8]                                  
00004260  e10300f9  str       x1, [sp]                                      
00004264  28008052  mov       w8, #1                                        
00004268  00010012  and       w0, w8, #1                                    
0000426c  ff430091  add       sp, sp, #0x10                                 
00004270  c0035fd6  ret                                                     

__ZL82_logos_method$_ungrouped$SBHomeScreenViewController$supportedInterfaceOrientationsP26SBHomeScreenViewControllerP13objc_selector
00004274  ff8300d1  sub       sp, sp, #0x20                                 
00004278  fd7b01a9  stp       x29, x30, [sp, #0x10]                         
0000427c  fd430091  add       x29, sp, #0x10                                
00004280  e00700f9  str       x0, [sp, #8]                                  
00004284  e10300f9  str       x1, [sp]                                      
00004288  28000090  adrp      x8, #0x8000                                   
0000428c  084540f9  ldr       x8, [x8, #0x88]                                ; __ZL80_logos_orig$_ungrouped$SBHomeScreenViewController$supportedInterfaceOrientations
00004290  e00740f9  ldr       x0, [sp, #8]                                  
00004294  e10340f9  ldr       x1, [sp]                                      
00004298  00013fd6  blr       x8                                            
0000429c  00007eb2  orr       x0, x0, #4                                    
000042a0  fd7b41a9  ldp       x29, x30, [sp, #0x10]                         
000042a4  ff830091  add       sp, sp, #0x20                                 
000042a8  c0035fd6  ret                                                     

__ZL96_logos_method$_ungrouped$SBCoverSheetPrimarySlidingViewController$supportedInterfaceOrientationsP40SBCoverSheetPrimarySlidingViewControllerP13objc_selector
000042ac  ff8300d1  sub       sp, sp, #0x20                                 
000042b0  fd7b01a9  stp       x29, x30, [sp, #0x10]                         
000042b4  fd430091  add       x29, sp, #0x10                                
000042b8  e00700f9  str       x0, [sp, #8]                                  
000042bc  e10300f9  str       x1, [sp]                                      
000042c0  28000090  adrp      x8, #0x8000                                   
000042c4  084940f9  ldr       x8, [x8, #0x90]                                ; __ZL94_logos_orig$_ungrouped$SBCoverSheetPrimarySlidingViewController$supportedInterfaceOrientations
000042c8  e00740f9  ldr       x0, [sp, #8]                                  
000042cc  e10340f9  ldr       x1, [sp]                                      
000042d0  00013fd6  blr       x8                                            
000042d4  00007eb2  orr       x0, x0, #4                                    
000042d8  fd7b41a9  ldp       x29, x30, [sp, #0x10]                         
000042dc  ff830091  add       sp, sp, #0x20                                 
000042e0  c0035fd6  ret                                                     