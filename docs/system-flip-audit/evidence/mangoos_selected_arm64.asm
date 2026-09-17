
; IMAGE 01-mangoos.dylib UNSLID FUNCTION 0x35c20
00035c20  7f2303d5  pacibsp                                                 
00035c24  fc6fbaa9  stp       x28, x27, [sp, #-0x60]!                       
00035c28  fa6701a9  stp       x26, x25, [sp, #0x10]                         
00035c2c  f85f02a9  stp       x24, x23, [sp, #0x20]                         
00035c30  f65703a9  stp       x22, x21, [sp, #0x30]                         
00035c34  f44f04a9  stp       x20, x19, [sp, #0x40]                         
00035c38  fd7b05a9  stp       x29, x30, [sp, #0x50]                         
00035c3c  fd430191  add       x29, sp, #0x50                                
00035c40  ff8312d1  sub       sp, sp, #0x4a0                                
00035c44  c80200f0  adrp      x8, #0x90000                                  
00035c48  08e943f9  ldr       x8, [x8, #0x7d0]                               ; ___stack_chk_guard
00035c4c  080140f9  ldr       x8, [x8]                                      
00035c50  a8031af8  stur      x8, [x29, #-0x60]                             
00035c54  def40094  bl        #0x72fcc                                       ; _objc_autoreleasePoolPush
00035c58  f60300aa  mov       x22, x0                                       
00035c5c  770300d0  adrp      x23, #0xa3000                                 
00035c60  e89645f9  ldr       x8, [x23, #0xb28]                             
00035c64  1f0500b1  cmn       x8, #1                                        
00035c68  a13f0054  b.ne      #0x3645c                                      
00035c6c  780300d0  adrp      x24, #0xa3000                                 
00035c70  089345f9  ldr       x8, [x24, #0xb20]                             
00035c74  1f4100f1  cmp       x8, #0x10                                     
00035c78  2b3d0054  b.lt      #0x3641c                                      
00035c7c  f6d00094  bl        #0x6a054                                       ; sub_0x6a054
00035c80  f40300aa  mov       x20, x0                                       
00035c84  60000036  tbz       w0, #0, #0x35c90                              
00035c88  19008052  mov       w25, #0                                       
00035c8c  16000014  b         #0x35ce4                                       ; sub_0x35ce4
00035c90  400200d0  adrp      x0, #0x7f000                                  
00035c94  00000191  add       x0, x0, #0x40                                  ; STR 'MRUActivityNowPlayingViewController'
00035c98  f1f40094  bl        #0x7305c                                       ; _objc_getClass
00035c9c  a00100b5  cbnz      x0, #0x35cd0                                  
00035ca0  400200d0  adrp      x0, #0x7f000                                  
00035ca4  00900191  add       x0, x0, #0x64                                  ; STR 'MRUSessionNowPlayingViewController'
00035ca8  edf40094  bl        #0x7305c                                       ; _objc_getClass
00035cac  200100b5  cbnz      x0, #0x35cd0                                  
00035cb0  400200d0  adrp      x0, #0x7f000                                  
00035cb4  001c0291  add       x0, x0, #0x87                                  ; STR 'MRUNowPlayingView'
00035cb8  e9f40094  bl        #0x7305c                                       ; _objc_getClass
00035cbc  a00000b5  cbnz      x0, #0x35cd0                                  
00035cc0  400200d0  adrp      x0, #0x7f000                                  
00035cc4  00640291  add       x0, x0, #0x99                                  ; STR 'MRULockscreenView'
00035cc8  e5f40094  bl        #0x7305c                                       ; _objc_getClass
00035ccc  e0fdffb4  cbz       x0, #0x35c88                                  
00035cd0  00008052  mov       w0, #0                                        
00035cd4  06ffff97  bl        #0x358ec                                       ; sub_0x358ec
00035cd8  000080d2  mov       x0, #0                                        
00035cdc  bf090094  bl        #0x383d8                                       ; sub_0x383d8
00035ce0  39008052  mov       w25, #1                                       
00035ce4  ff4b00f9  str       xzr, [sp, #0x90]                              
00035ce8  e0430291  add       x0, sp, #0x90                                 
00035cec  01020094  bl        #0x364f0                                       ; sub_0x364f0
00035cf0  f34b40f9  ldr       x19, [sp, #0x90]                              
00035cf4  7f0200f1  cmp       x19, #0                                       
00035cf8  faa3801a  csel      w26, wzr, w0, ge                              
00035cfc  9cd00094  bl        #0x69f6c                                       ; sub_0x69f6c
00035d00  fd031daa  mov       x29, x29                                      
00035d04  0af50094  bl        #0x7312c                                       ; _objc_retainAutoreleasedReturnValue
00035d08  f50300aa  mov       x21, x0                                       
00035d0c  e89645f9  ldr       x8, [x23, #0xb28]                             
00035d10  1f0500b1  cmn       x8, #1                                        
00035d14  f64700f9  str       x22, [sp, #0x88]                              
00035d18  f48700b9  str       w20, [sp, #0x84]                              
00035d1c  fae706a9  stp       x26, x25, [sp, #0x68]                         
00035d20  a13a0054  b.ne      #0x36474                                      
00035d24  149345f9  ldr       x20, [x24, #0xb20]                            
00035d28  83d20094  bl        #0x6a734                                       ; sub_0x6a734
00035d2c  f60300aa  mov       x22, x0                                       
00035d30  000300b0  adrp      x0, #0x96000                                  
00035d34  00800591  add       x0, x0, #0x160                                 ; CFSTR 'MediaVolume.Enabled'
00035d38  01008052  mov       w1, #0                                        
00035d3c  d2d10094  bl        #0x6a484                                       ; sub_0x6a484
00035d40  f70300aa  mov       x23, x0                                       
00035d44  000300b0  adrp      x0, #0x96000                                  
00035d48  00000691  add       x0, x0, #0x180                                 ; CFSTR 'MediaVolume.LockScreen'
00035d4c  01008052  mov       w1, #0                                        
00035d50  cdd10094  bl        #0x6a484                                       ; sub_0x6a484
00035d54  f80300aa  mov       x24, x0                                       
00035d58  000300b0  adrp      x0, #0x96000                                  
00035d5c  00800691  add       x0, x0, #0x1a0                                 ; CFSTR 'MediaVolume.DynamicIsland'
00035d60  01008052  mov       w1, #0                                        
00035d64  c8d10094  bl        #0x6a484                                       ; sub_0x6a484
00035d68  f90300aa  mov       x25, x0                                       
00035d6c  400200d0  adrp      x0, #0x7f000                                  
00035d70  00ec0591  add       x0, x0, #0x17b                                 ; STR 'MRUNowPlayingVolumeControlsView'
00035d74  baf40094  bl        #0x7305c                                       ; _objc_getClass
00035d78  1f0000f1  cmp       x0, #0                                        
00035d7c  fb079f1a  cset      w27, ne                                       
00035d80  400200d0  adrp      x0, #0x7f000                                  
00035d84  00000191  add       x0, x0, #0x40                                  ; STR 'MRUActivityNowPlayingViewController'
00035d88  b5f40094  bl        #0x7305c                                       ; _objc_getClass
00035d8c  1f0000f1  cmp       x0, #0                                        
00035d90  fc079f1a  cset      w28, ne                                       
00035d94  400200d0  adrp      x0, #0x7f000                                  
00035d98  001c0291  add       x0, x0, #0x87                                  ; STR 'MRUNowPlayingView'
00035d9c  b0f40094  bl        #0x7305c                                       ; _objc_getClass
00035da0  1f0000f1  cmp       x0, #0                                        
00035da4  fa079f1a  cset      w26, ne                                       
00035da8  400200d0  adrp      x0, #0x7f000                                  
00035dac  00640291  add       x0, x0, #0x99                                  ; STR 'MRULockscreenView'
00035db0  abf40094  bl        #0x7305c                                       ; _objc_getClass
00035db4  1f0000f1  cmp       x0, #0                                        
00035db8  e8079f1a  cset      w8, ne                                        
00035dbc  fc6b05a9  stp       x28, x26, [sp, #0x50]                         
00035dc0  e903192a  mov       w9, w25                                       
00035dc4  e96f04a9  stp       x9, x27, [sp, #0x40]                          
00035dc8  e903182a  mov       w9, w24                                       
00035dcc  ea03172a  mov       w10, w23                                      
00035dd0  ea2703a9  stp       x10, x9, [sp, #0x30]                          
00035dd4  e903162a  mov       w9, w22                                       
00035dd8  f32702a9  stp       x19, x9, [sp, #0x20]                          
00035ddc  eb3740f9  ldr       x11, [sp, #0x68]                              
00035de0  e93b40f9  ldr       x9, [sp, #0x70]                               
00035de4  e92f01a9  stp       x9, x11, [sp, #0x10]                          
00035de8  f55300a9  stp       x21, x20, [sp]                                
00035dec  e83300f9  str       x8, [sp, #0x60]                               
00035df0  fb010094  bl        #0x365dc                                       ; sub_0x365dc
00035df4  e00315aa  mov       x0, x21                                       
00035df8  bdf40094  bl        #0x730ec                                       ; _objc_release
00035dfc  f38740b9  ldr       w19, [sp, #0x84]                              
00035e00  d3060034  cbz       w19, #0x35ed8                                 
00035e04  4cd20094  bl        #0x6a734                                       ; sub_0x6a734
00035e08  f50300aa  mov       x21, x0                                       
00035e0c  000300b0  adrp      x0, #0x96000                                  
00035e10  00800591  add       x0, x0, #0x160                                 ; CFSTR 'MediaVolume.Enabled'
00035e14  01008052  mov       w1, #0                                        
00035e18  9bd10094  bl        #0x6a484                                       ; sub_0x6a484
00035e1c  f60300aa  mov       x22, x0                                       
00035e20  000300b0  adrp      x0, #0x96000                                  
00035e24  00000691  add       x0, x0, #0x180                                 ; CFSTR 'MediaVolume.LockScreen'
00035e28  01008052  mov       w1, #0                                        
00035e2c  96d10094  bl        #0x6a484                                       ; sub_0x6a484
00035e30  f70300aa  mov       x23, x0                                       
00035e34  000300b0  adrp      x0, #0x96000                                  
00035e38  00800691  add       x0, x0, #0x1a0                                 ; CFSTR 'MediaVolume.DynamicIsland'
00035e3c  01008052  mov       w1, #0                                        
00035e40  91d10094  bl        #0x6a484                                       ; sub_0x6a484
00035e44  f80300aa  mov       x24, x0                                       
00035e48  680300d0  adrp      x8, #0xa3000                                  
00035e4c  08a945f9  ldr       x8, [x8, #0xb50]                              
00035e50  1f0500b1  cmn       x8, #1                                        
00035e54  01340054  b.ne      #0x364d4                                      
00035e58  680300d0  adrp      x8, #0xa3000                                  
00035e5c  190d40b9  ldr       w25, [x8, #0xc]                               
00035e60  ff4b00f9  str       xzr, [sp, #0x90]                              
00035e64  3f070031  cmn       w25, #1                                       
00035e68  e0000054  b.eq      #0x35e84                                      
00035e6c  e1430291  add       x1, sp, #0x90                                 
00035e70  e00319aa  mov       x0, x25                                       
00035e74  32f40094  bl        #0x72f3c                                       ; _notify_get_state
00035e78  e84b40f9  ldr       x8, [sp, #0x90]                               
00035e7c  08e97c92  and       x8, x8, #0x7ffffffffffffff0                   
00035e80  02000014  b         #0x35e88                                       ; sub_0x35e88
00035e84  080080d2  mov       x8, #0                                        
00035e88  09017db2  orr       x9, x8, #8                                    
00035e8c  bf020071  cmp       w21, #0                                       
00035e90  2811889a  csel      x8, x9, x8, ne                                
00035e94  e903162a  mov       w9, w22                                       
00035e98  080109aa  orr       x8, x8, x9                                    
00035e9c  09017fb2  orr       x9, x8, #2                                    
00035ea0  ff020071  cmp       w23, #0                                       
00035ea4  2811889a  csel      x8, x9, x8, ne                                
00035ea8  09017eb2  orr       x9, x8, #4                                    
00035eac  1f030071  cmp       w24, #0                                       
00035eb0  2811889a  csel      x8, x9, x8, ne                                
00035eb4  010141b2  orr       x1, x8, #0x8000000000000000                   
00035eb8  e14b00f9  str       x1, [sp, #0x90]                               
00035ebc  3f070031  cmn       w25, #1                                       
00035ec0  60000054  b.eq      #0x35ecc                                      
00035ec4  e00319aa  mov       x0, x25                                       
00035ec8  2df40094  bl        #0x72f7c                                       ; _notify_set_state
00035ecc  400200d0  adrp      x0, #0x7f000                                  
00035ed0  00f00991  add       x0, x0, #0x27c                                 ; STR 'go.mangoos/mediavolume.state'
00035ed4  1ef40094  bl        #0x72f4c                                       ; _notify_post
00035ed8  400200d0  adrp      x0, #0x7f000                                  
00035edc  00ec0591  add       x0, x0, #0x17b                                 ; STR 'MRUNowPlayingVolumeControlsView'
00035ee0  5ff40094  bl        #0x7305c                                       ; _objc_getClass
00035ee4  f64740f9  ldr       x22, [sp, #0x88]                              
00035ee8  740300d0  adrp      x20, #0xa3000                                 
00035eec  770300d0  adrp      x23, #0xa3000                                 
00035ef0  e00b00b4  cbz       x0, #0x3606c                                  
00035ef4  400200d0  adrp      x0, #0x7f000                                  
00035ef8  00ec0591  add       x0, x0, #0x17b                                 ; STR 'MRUNowPlayingVolumeControlsView'
00035efc  58f40094  bl        #0x7305c                                       ; _objc_getClass
00035f00  f50300aa  mov       x21, x0                                       
00035f04  68030090  adrp      x8, #0xa1000                                  
00035f08  014d44f9  ldr       x1, [x8, #0x898]                               ; SEL didMoveToWindow
00035f0c  630300d0  adrp      x3, #0xa3000                                  
00035f10  63802991  add       x3, x3, #0xa60                                
00035f14  100000b0  adrp      x16, #0x36000                                 
00035f18  10621b91  add       x16, x16, #0x6d8                              
00035f1c  f023c1da  paciza    x16                                           
00035f20  e20310aa  mov       x2, x16                                       
00035f24  cef20094  bl        #0x72a5c                                       ; _MSHookMessageEx
00035f28  68030090  adrp      x8, #0xa1000                                  
00035f2c  012545f9  ldr       x1, [x8, #0xa48]                               ; SEL volumeController:volumeControlAvailableDidChange:
00035f30  630300d0  adrp      x3, #0xa3000                                  
00035f34  63a02991  add       x3, x3, #0xa68                                
00035f38  100000b0  adrp      x16, #0x36000                                 
00035f3c  10f22291  add       x16, x16, #0x8bc                              
00035f40  f023c1da  paciza    x16                                           
00035f44  e20310aa  mov       x2, x16                                       
00035f48  e00315aa  mov       x0, x21                                       
00035f4c  c4f20094  bl        #0x72a5c                                       ; _MSHookMessageEx
00035f50  68030090  adrp      x8, #0xa1000                                  
00035f54  012945f9  ldr       x1, [x8, #0xa50]                               ; SEL isOnScreen
00035f58  630300d0  adrp      x3, #0xa3000                                  
00035f5c  63c02991  add       x3, x3, #0xa70                                
00035f60  100000b0  adrp      x16, #0x36000                                 
00035f64  10a22a91  add       x16, x16, #0xaa8                              
00035f68  f023c1da  paciza    x16                                           
00035f6c  e20310aa  mov       x2, x16                                       
00035f70  e00315aa  mov       x0, x21                                       
00035f74  baf20094  bl        #0x72a5c                                       ; _MSHookMessageEx
00035f78  400200d0  adrp      x0, #0x7f000                                  
00035f7c  006c0691  add       x0, x0, #0x19b                                 ; STR 'MRUSlider'
00035f80  37f40094  bl        #0x7305c                                       ; _objc_getClass
00035f84  480300f0  adrp      x8, #0xa0000                                  
00035f88  010146f9  ldr       x1, [x8, #0xc00]                               ; SEL setEnabled:
00035f8c  630300d0  adrp      x3, #0xa3000                                  
00035f90  63e02991  add       x3, x3, #0xa78                                
00035f94  100000b0  adrp      x16, #0x36000                                 
00035f98  10622c91  add       x16, x16, #0xb18                              
00035f9c  f023c1da  paciza    x16                                           
00035fa0  e20310aa  mov       x2, x16                                       
00035fa4  aef20094  bl        #0x72a5c                                       ; _MSHookMessageEx
00035fa8  889645f9  ldr       x8, [x20, #0xb28]                             
00035fac  1f0500b1  cmn       x8, #1                                        
00035fb0  61280054  b.ne      #0x364bc                                      
00035fb4  e89245f9  ldr       x8, [x23, #0xb20]                             
00035fb8  1f4100f1  cmp       x8, #0x10                                     
00035fbc  e1050054  b.ne      #0x36078                                      
00035fc0  400200d0  adrp      x0, #0x7f000                                  
00035fc4  006c0691  add       x0, x0, #0x19b                                 ; STR 'MRUSlider'
00035fc8  25f40094  bl        #0x7305c                                       ; _objc_getClass
00035fcc  f50300aa  mov       x21, x0                                       
00035fd0  68030090  adrp      x8, #0xa1000                                  
00035fd4  01b544f9  ldr       x1, [x8, #0x968]                               ; SEL beginTrackingWithTouch:withEvent:
00035fd8  630300d0  adrp      x3, #0xa3000                                  
00035fdc  63002a91  add       x3, x3, #0xa80                                
00035fe0  100000b0  adrp      x16, #0x36000                                 
00035fe4  10a22e91  add       x16, x16, #0xba8                              
00035fe8  f023c1da  paciza    x16                                           
00035fec  e20310aa  mov       x2, x16                                       
00035ff0  9bf20094  bl        #0x72a5c                                       ; _MSHookMessageEx
00035ff4  68030090  adrp      x8, #0xa1000                                  
00035ff8  01b944f9  ldr       x1, [x8, #0x970]                               ; SEL continueTrackingWithTouch:withEvent:
00035ffc  630300d0  adrp      x3, #0xa3000                                  
00036000  63202a91  add       x3, x3, #0xa88                                
00036004  10000090  adrp      x16, #0x36000                                 
00036008  10323191  add       x16, x16, #0xc4c                              
0003600c  f023c1da  paciza    x16                                           
00036010  e20310aa  mov       x2, x16                                       
00036014  e00315aa  mov       x0, x21                                       
00036018  91f20094  bl        #0x72a5c                                       ; _MSHookMessageEx
0003601c  480300f0  adrp      x8, #0xa1000                                  
00036020  01bd44f9  ldr       x1, [x8, #0x978]                               ; SEL endTrackingWithTouch:withEvent:
00036024  630300b0  adrp      x3, #0xa3000                                  
00036028  63402a91  add       x3, x3, #0xa90                                
0003602c  10000090  adrp      x16, #0x36000                                 
00036030  10c23291  add       x16, x16, #0xcb0                              
00036034  f023c1da  paciza    x16                                           
00036038  e20310aa  mov       x2, x16                                       
0003603c  e00315aa  mov       x0, x21                                       
00036040  87f20094  bl        #0x72a5c                                       ; _MSHookMessageEx
00036044  480300f0  adrp      x8, #0xa1000                                  
00036048  01a944f9  ldr       x1, [x8, #0x950]                               ; SEL cancelTrackingWithEvent:
0003604c  630300b0  adrp      x3, #0xa3000                                  
00036050  63602a91  add       x3, x3, #0xa98                                
00036054  10000090  adrp      x16, #0x36000                                 
00036058  10d23491  add       x16, x16, #0xd34                              
0003605c  f023c1da  paciza    x16                                           
00036060  e20310aa  mov       x2, x16                                       
00036064  e00315aa  mov       x0, x21                                       
00036068  7df20094  bl        #0x72a5c                                       ; _MSHookMessageEx
0003606c  889645f9  ldr       x8, [x20, #0xb28]                             
00036070  1f0500b1  cmn       x8, #1                                        
00036074  c1200054  b.ne      #0x3648c                                      
00036078  e89245f9  ldr       x8, [x23, #0xb20]                             
0003607c  1f4500f1  cmp       x8, #0x11                                     
00036080  6c0c0054  b.gt      #0x3620c                                      
00036084  400200b0  adrp      x0, #0x7f000                                  
00036088  001c0291  add       x0, x0, #0x87                                  ; STR 'MRUNowPlayingView'
0003608c  f4f30094  bl        #0x7305c                                       ; _objc_getClass
00036090  800b00b4  cbz       x0, #0x36200                                  
00036094  400200b0  adrp      x0, #0x7f000                                  
00036098  001c0291  add       x0, x0, #0x87                                  ; STR 'MRUNowPlayingView'
0003609c  f0f30094  bl        #0x7305c                                       ; _objc_getClass
000360a0  f50300aa  mov       x21, x0                                       
000360a4  480300f0  adrp      x8, #0xa1000                                  
000360a8  010d40f9  ldr       x1, [x8, #0x18]                                ; SEL setShowVolumeControlsView:
000360ac  630300b0  adrp      x3, #0xa3000                                  
000360b0  63802a91  add       x3, x3, #0xaa0                                
000360b4  10000090  adrp      x16, #0x36000                                 
000360b8  10e23691  add       x16, x16, #0xdb8                              
000360bc  f023c1da  paciza    x16                                           
000360c0  e20310aa  mov       x2, x16                                       
000360c4  66f20094  bl        #0x72a5c                                       ; _MSHookMessageEx
000360c8  480300f0  adrp      x8, #0xa1000                                  
000360cc  010543f9  ldr       x1, [x8, #0x608]                               ; SEL updateVisibility
000360d0  630300b0  adrp      x3, #0xa3000                                  
000360d4  63a02a91  add       x3, x3, #0xaa8                                
000360d8  10000090  adrp      x16, #0x36000                                 
000360dc  10423891  add       x16, x16, #0xe10                              
000360e0  f023c1da  paciza    x16                                           
000360e4  e20310aa  mov       x2, x16                                       
000360e8  e00315aa  mov       x0, x21                                       
000360ec  5cf20094  bl        #0x72a5c                                       ; _MSHookMessageEx
000360f0  400200b0  adrp      x0, #0x7f000                                  
000360f4  00940691  add       x0, x0, #0x1a5                                 ; STR 'MRUNowPlayingViewController'
000360f8  d9f30094  bl        #0x7305c                                       ; _objc_getClass
000360fc  f50300aa  mov       x21, x0                                       
00036100  480300f0  adrp      x8, #0xa1000                                  
00036104  015944f9  ldr       x1, [x8, #0x8b0]                               ; SEL viewDidLoad
00036108  630300b0  adrp      x3, #0xa3000                                  
0003610c  63c02a91  add       x3, x3, #0xab0                                
00036110  10000090  adrp      x16, #0x36000                                 
00036114  10e23991  add       x16, x16, #0xe78                              
00036118  f023c1da  paciza    x16                                           
0003611c  e20310aa  mov       x2, x16                                       
00036120  4ff20094  bl        #0x72a5c                                       ; _MSHookMessageEx
00036124  480300f0  adrp      x8, #0xa1000                                  
00036128  016d44f9  ldr       x1, [x8, #0x8d8]                               ; SEL viewDidDisappear:
0003612c  630300b0  adrp      x3, #0xa3000                                  
00036130  63e02a91  add       x3, x3, #0xab8                                
00036134  10000090  adrp      x16, #0x36000                                 
00036138  10223b91  add       x16, x16, #0xec8                              
0003613c  f023c1da  paciza    x16                                           
00036140  e20310aa  mov       x2, x16                                       
00036144  e00315aa  mov       x0, x21                                       
00036148  45f20094  bl        #0x72a5c                                       ; _MSHookMessageEx
0003614c  480300f0  adrp      x8, #0xa1000                                  
00036150  016544f9  ldr       x1, [x8, #0x8c8]                               ; SEL viewWillAppear:
00036154  630300b0  adrp      x3, #0xa3000                                  
00036158  63002b91  add       x3, x3, #0xac0                                
0003615c  10000090  adrp      x16, #0x36000                                 
00036160  10123d91  add       x16, x16, #0xf44                              
00036164  f023c1da  paciza    x16                                           
00036168  e20310aa  mov       x2, x16                                       
0003616c  e00315aa  mov       x0, x21                                       
00036170  3bf20094  bl        #0x72a5c                                       ; _MSHookMessageEx
00036174  480200f0  adrp      x8, #0x81000                                  
00036178  006144fd  ldr       d0, [x8, #0x8c0]                              
0003617c  e01f803d  str       q0, [sp, #0x70]                               
00036180  e09300bd  str       s0, [sp, #0x90]                               
00036184  480300d0  adrp      x8, #0xa0000                                  
00036188  015d42f9  ldr       x1, [x8, #0x4b8]                               ; SEL mgmv_stampHostAndForce
0003618c  100000b0  adrp      x16, #0x37000                                 
00036190  10020091  add       x16, x16, #0                                  
00036194  f023c1da  paciza    x16                                           
00036198  e20310aa  mov       x2, x16                                       
0003619c  e3430291  add       x3, sp, #0x90                                 
000361a0  e00315aa  mov       x0, x21                                       
000361a4  9ef20094  bl        #0x72c1c                                       ; _class_addMethod
000361a8  e01fc03d  ldr       q0, [sp, #0x70]                               
000361ac  e09300bd  str       s0, [sp, #0x90]                               
000361b0  480300f0  adrp      x8, #0xa1000                                  
000361b4  012d45f9  ldr       x1, [x8, #0xa58]                               ; SEL mgmv_prefsChanged
000361b8  100000b0  adrp      x16, #0x37000                                 
000361bc  10f20b91  add       x16, x16, #0x2fc                              
000361c0  f023c1da  paciza    x16                                           
000361c4  e20310aa  mov       x2, x16                                       
000361c8  e3430291  add       x3, sp, #0x90                                 
000361cc  e00315aa  mov       x0, x21                                       
000361d0  93f20094  bl        #0x72c1c                                       ; _class_addMethod
000361d4  e01fc03d  ldr       q0, [sp, #0x70]                               
000361d8  e09300bd  str       s0, [sp, #0x90]                               
000361dc  480300d0  adrp      x8, #0xa0000                                  
000361e0  016142f9  ldr       x1, [x8, #0x4c0]                               ; SEL mgmv_syncHeight
000361e4  100000b0  adrp      x16, #0x37000                                 
000361e8  10d20c91  add       x16, x16, #0x334                              
000361ec  f023c1da  paciza    x16                                           
000361f0  e20310aa  mov       x2, x16                                       
000361f4  e3430291  add       x3, sp, #0x90                                 
000361f8  e00315aa  mov       x0, x21                                       
000361fc  88f20094  bl        #0x72c1c                                       ; _class_addMethod
00036200  889645f9  ldr       x8, [x20, #0xb28]                             
00036204  1f0500b1  cmn       x8, #1                                        
00036208  e1140054  b.ne      #0x364a4                                      
0003620c  e89245f9  ldr       x8, [x23, #0xb20]                             
00036210  1f4900f1  cmp       x8, #0x12                                     
00036214  6b090054  b.lt      #0x36340                                      
00036218  06050094  bl        #0x37630                                       ; sub_0x37630
0003621c  20090037  tbnz      w0, #0, #0x36340                              
00036220  400200b0  adrp      x0, #0x7f000                                  
00036224  00640291  add       x0, x0, #0x99                                  ; STR 'MRULockscreenView'
00036228  8df30094  bl        #0x7305c                                       ; _objc_getClass
0003622c  a00800b4  cbz       x0, #0x36340                                  
00036230  400200b0  adrp      x0, #0x7f000                                  
00036234  00640291  add       x0, x0, #0x99                                  ; STR 'MRULockscreenView'
00036238  89f30094  bl        #0x7305c                                       ; _objc_getClass
0003623c  f50300aa  mov       x21, x0                                       
00036240  480300f0  adrp      x8, #0xa1000                                  
00036244  010d40f9  ldr       x1, [x8, #0x18]                                ; SEL setShowVolumeControlsView:
00036248  630300b0  adrp      x3, #0xa3000                                  
0003624c  63202b91  add       x3, x3, #0xac8                                
00036250  100000b0  adrp      x16, #0x37000                                 
00036254  10221a91  add       x16, x16, #0x688                              
00036258  f023c1da  paciza    x16                                           
0003625c  e20310aa  mov       x2, x16                                       
00036260  fff10094  bl        #0x72a5c                                       ; _MSHookMessageEx
00036264  480300f0  adrp      x8, #0xa1000                                  
00036268  010543f9  ldr       x1, [x8, #0x608]                               ; SEL updateVisibility
0003626c  630300b0  adrp      x3, #0xa3000                                  
00036270  63402b91  add       x3, x3, #0xad0                                
00036274  100000b0  adrp      x16, #0x37000                                 
00036278  10221d91  add       x16, x16, #0x748                              
0003627c  f023c1da  paciza    x16                                           
00036280  e20310aa  mov       x2, x16                                       
00036284  e00315aa  mov       x0, x21                                       
00036288  f5f10094  bl        #0x72a5c                                       ; _MSHookMessageEx
0003628c  400200b0  adrp      x0, #0x7f000                                  
00036290  00040791  add       x0, x0, #0x1c1                                 ; STR 'MRULockscreenViewController'
00036294  72f30094  bl        #0x7305c                                       ; _objc_getClass
00036298  f50300aa  mov       x21, x0                                       
0003629c  480300f0  adrp      x8, #0xa1000                                  
000362a0  015944f9  ldr       x1, [x8, #0x8b0]                               ; SEL viewDidLoad
000362a4  630300b0  adrp      x3, #0xa3000                                  
000362a8  63602b91  add       x3, x3, #0xad8                                
000362ac  100000b0  adrp      x16, #0x37000                                 
000362b0  10c21e91  add       x16, x16, #0x7b0                              
000362b4  f023c1da  paciza    x16                                           
000362b8  e20310aa  mov       x2, x16                                       
000362bc  e8f10094  bl        #0x72a5c                                       ; _MSHookMessageEx
000362c0  480300f0  adrp      x8, #0xa1000                                  
000362c4  016d44f9  ldr       x1, [x8, #0x8d8]                               ; SEL viewDidDisappear:
000362c8  630300b0  adrp      x3, #0xa3000                                  
000362cc  63802b91  add       x3, x3, #0xae0                                
000362d0  100000b0  adrp      x16, #0x37000                                 
000362d4  10022091  add       x16, x16, #0x800                              
000362d8  f023c1da  paciza    x16                                           
000362dc  e20310aa  mov       x2, x16                                       
000362e0  e00315aa  mov       x0, x21                                       
000362e4  def10094  bl        #0x72a5c                                       ; _MSHookMessageEx
000362e8  480300f0  adrp      x8, #0xa1000                                  
000362ec  016544f9  ldr       x1, [x8, #0x8c8]                               ; SEL viewWillAppear:
000362f0  630300b0  adrp      x3, #0xa3000                                  
000362f4  63a02b91  add       x3, x3, #0xae8                                
000362f8  100000b0  adrp      x16, #0x37000                                 
000362fc  10e22091  add       x16, x16, #0x838                              
00036300  f023c1da  paciza    x16                                           
00036304  e20310aa  mov       x2, x16                                       
00036308  e00315aa  mov       x0, x21                                       
0003630c  d4f10094  bl        #0x72a5c                                       ; _MSHookMessageEx
00036310  480200f0  adrp      x8, #0x81000                                  
00036314  006144fd  ldr       d0, [x8, #0x8c0]                              
00036318  e09300bd  str       s0, [sp, #0x90]                               
0003631c  480300d0  adrp      x8, #0xa0000                                  
00036320  015942f9  ldr       x1, [x8, #0x4b0]                               ; SEL mgmv_ls18Apply
00036324  100000b0  adrp      x16, #0x37000                                 
00036328  10d22391  add       x16, x16, #0x8f4                              
0003632c  f023c1da  paciza    x16                                           
00036330  e20310aa  mov       x2, x16                                       
00036334  e3430291  add       x3, sp, #0x90                                 
00036338  e00315aa  mov       x0, x21                                       
0003633c  38f20094  bl        #0x72c1c                                       ; _class_addMethod
00036340  100000b0  adrp      x16, #0x37000                                 
00036344  10722b91  add       x16, x16, #0xadc                              
00036348  f023c1da  paciza    x16                                           
0003634c  e00310aa  mov       x0, x16                                       
00036350  17f20094  bl        #0x72bac                                       ; __dyld_register_func_for_add_image
00036354  53060034  cbz       w19, #0x3641c                                 
00036358  400200b0  adrp      x0, #0x7f000                                  
0003635c  00740791  add       x0, x0, #0x1dd                                 ; STR 'SBVolumeControl'
00036360  3ff30094  bl        #0x7305c                                       ; _objc_getClass
00036364  480300f0  adrp      x8, #0xa1000                                  
00036368  013145f9  ldr       x1, [x8, #0xa60]                               ; SEL _presentVolumeHUDWithVolume:
0003636c  630300b0  adrp      x3, #0xa3000                                  
00036370  63c02b91  add       x3, x3, #0xaf0                                
00036374  100000b0  adrp      x16, #0x37000                                 
00036378  10f23f91  add       x16, x16, #0xffc                              
0003637c  f023c1da  paciza    x16                                           
00036380  e20310aa  mov       x2, x16                                       
00036384  b6f10094  bl        #0x72a5c                                       ; _MSHookMessageEx
00036388  400200b0  adrp      x0, #0x7f000                                  
0003638c  00b40791  add       x0, x0, #0x1ed                                 ; STR 'SBSystemApertureResizeGestureRecognizer'
00036390  33f30094  bl        #0x7305c                                       ; _objc_getClass
00036394  f40300aa  mov       x20, x0                                       
00036398  480300f0  adrp      x8, #0xa1000                                  
0003639c  01c144f9  ldr       x1, [x8, #0x980]                               ; SEL touchesBegan:withEvent:
000363a0  630300b0  adrp      x3, #0xa3000                                  
000363a4  63e02b91  add       x3, x3, #0xaf8                                
000363a8  100000d0  adrp      x16, #0x38000                                 
000363ac  10220591  add       x16, x16, #0x148                              
000363b0  f023c1da  paciza    x16                                           
000363b4  e20310aa  mov       x2, x16                                       
000363b8  a9f10094  bl        #0x72a5c                                       ; _MSHookMessageEx
000363bc  480300f0  adrp      x8, #0xa1000                                  
000363c0  15c544f9  ldr       x21, [x8, #0x988]                              ; SEL touchesMoved:withEvent:
000363c4  630300b0  adrp      x3, #0xa3000                                  
000363c8  63002c91  add       x3, x3, #0xb00                                
000363cc  100000d0  adrp      x16, #0x38000                                 
000363d0  10820791  add       x16, x16, #0x1e0                              
000363d4  f023c1da  paciza    x16                                           
000363d8  e20310aa  mov       x2, x16                                       
000363dc  e00314aa  mov       x0, x20                                       
000363e0  e10315aa  mov       x1, x21                                       
000363e4  9ef10094  bl        #0x72a5c                                       ; _MSHookMessageEx
000363e8  400200b0  adrp      x0, #0x7f000                                  
000363ec  00540891  add       x0, x0, #0x215                                 ; STR 'SBSystemApertureLongPressGestureRecognizer'
000363f0  1bf30094  bl        #0x7305c                                       ; _objc_getClass
000363f4  630300b0  adrp      x3, #0xa3000                                  
000363f8  63202c91  add       x3, x3, #0xb08                                
000363fc  100000d0  adrp      x16, #0x38000                                 
00036400  10e20991  add       x16, x16, #0x278                              
00036404  f023c1da  paciza    x16                                           
00036408  e20310aa  mov       x2, x16                                       
0003640c  e10315aa  mov       x1, x21                                       
00036410  93f10094  bl        #0x72a5c                                       ; _MSHookMessageEx
00036414  000080d2  mov       x0, #0                                        
00036418  f0070094  bl        #0x383d8                                       ; sub_0x383d8
0003641c  e00316aa  mov       x0, x22                                       
00036420  e7f20094  bl        #0x72fbc                                       ; _objc_autoreleasePoolPop
00036424  a8035af8  ldur      x8, [x29, #-0x60]                             
00036428  c90200d0  adrp      x9, #0x90000                                  
0003642c  29e943f9  ldr       x9, [x9, #0x7d0]                               ; ___stack_chk_guard
00036430  290140f9  ldr       x9, [x9]                                      
00036434  3f0108eb  cmp       x9, x8                                        
00036438  a1050054  b.ne      #0x364ec                                      
0003643c  ff831291  add       sp, sp, #0x4a0                                
00036440  fd7b45a9  ldp       x29, x30, [sp, #0x50]                         
00036444  f44f44a9  ldp       x20, x19, [sp, #0x40]                         
00036448  f65743a9  ldp       x22, x21, [sp, #0x30]                         
0003644c  f85f42a9  ldp       x24, x23, [sp, #0x20]                         
00036450  fa6741a9  ldp       x26, x25, [sp, #0x10]                         
00036454  fc6fc6a8  ldp       x28, x27, [sp], #0x60                         
00036458  ff0f5fd6  retab                                                   
0003645c  600300b0  adrp      x0, #0xa3000                                  
00036460  00a02c91  add       x0, x0, #0xb28                                
00036464  c10200f0  adrp      x1, #0x91000                                  
00036468  21400f91  add       x1, x1, #0x3d0                                 ; __NSConcreteGlobalBlock
0003646c  20f20094  bl        #0x72cec                                       ; _dispatch_once
00036470  fffdff17  b         #0x35c6c                                       ; sub_0x35c6c
00036474  600300b0  adrp      x0, #0xa3000                                  
00036478  00a02c91  add       x0, x0, #0xb28                                
0003647c  c10200f0  adrp      x1, #0x91000                                  
00036480  21400f91  add       x1, x1, #0x3d0                                 ; __NSConcreteGlobalBlock
00036484  1af20094  bl        #0x72cec                                       ; _dispatch_once
00036488  27feff17  b         #0x35d24                                       ; sub_0x35d24
0003648c  600300b0  adrp      x0, #0xa3000                                  
00036490  00a02c91  add       x0, x0, #0xb28                                
00036494  c10200f0  adrp      x1, #0x91000                                  
00036498  21400f91  add       x1, x1, #0x3d0                                 ; __NSConcreteGlobalBlock
0003649c  14f20094  bl        #0x72cec                                       ; _dispatch_once
000364a0  f6feff17  b         #0x36078                                       ; sub_0x36078
000364a4  600300b0  adrp      x0, #0xa3000                                  
000364a8  00a02c91  add       x0, x0, #0xb28                                
000364ac  c10200f0  adrp      x1, #0x91000                                  
000364b0  21400f91  add       x1, x1, #0x3d0                                 ; __NSConcreteGlobalBlock
000364b4  0ef20094  bl        #0x72cec                                       ; _dispatch_once
000364b8  55ffff17  b         #0x3620c                                       ; sub_0x3620c
000364bc  600300b0  adrp      x0, #0xa3000                                  
000364c0  00a02c91  add       x0, x0, #0xb28                                
000364c4  c10200f0  adrp      x1, #0x91000                                  
000364c8  21400f91  add       x1, x1, #0x3d0                                 ; __NSConcreteGlobalBlock
000364cc  08f20094  bl        #0x72cec                                       ; _dispatch_once
000364d0  b9feff17  b         #0x35fb4                                       ; sub_0x35fb4
000364d4  600300b0  adrp      x0, #0xa3000                                  
000364d8  00402d91  add       x0, x0, #0xb50                                
000364dc  c10200f0  adrp      x1, #0x91000                                  
000364e0  21c01091  add       x1, x1, #0x430                                 ; __NSConcreteGlobalBlock
000364e4  02f20094  bl        #0x72cec                                       ; _dispatch_once
000364e8  5cfeff17  b         #0x35e58                                       ; sub_0x35e58
000364ec  a8f10094  bl        #0x72b8c                                       ; ___stack_chk_fail

; IMAGE 01-mangoos.dylib UNSLID FUNCTION 0x38148
00038148  7f2303d5  pacibsp                                                 
0003814c  f657bda9  stp       x22, x21, [sp, #-0x30]!                       
00038150  f44f01a9  stp       x20, x19, [sp, #0x10]                         
00038154  fd7b02a9  stp       x29, x30, [sp, #0x20]                         
00038158  fd830091  add       x29, sp, #0x20                                
0003815c  f40303aa  mov       x20, x3                                       
00038160  f60301aa  mov       x22, x1                                       
00038164  f50300aa  mov       x21, x0                                       
00038168  e00302aa  mov       x0, x2                                        
0003816c  e4eb0094  bl        #0x730fc                                       ; _objc_retain
00038170  f30300aa  mov       x19, x0                                       
00038174  e00314aa  mov       x0, x20                                       
00038178  e1eb0094  bl        #0x730fc                                       ; _objc_retain
0003817c  f40300aa  mov       x20, x0                                       
00038180  02080094  bl        #0x3a188                                       ; sub_0x3a188
00038184  a0000034  cbz       w0, #0x38198                                  
00038188  e00315aa  mov       x0, x21                                       
0003818c  a2008052  mov       w2, #5                                        
00038190  c4040194  bl        #0x794a0                                       ; objc_msgSend$setState:
00038194  08000014  b         #0x381b4                                       ; sub_0x381b4
00038198  480300f0  adrp      x8, #0xa3000                                  
0003819c  087d45f9  ldr       x8, [x8, #0xaf8]                              
000381a0  e00315aa  mov       x0, x21                                       
000381a4  e10316aa  mov       x1, x22                                       
000381a8  e20313aa  mov       x2, x19                                       
000381ac  e30314aa  mov       x3, x20                                       
000381b0  1f093fd6  blraaz    x8                                            
000381b4  e00314aa  mov       x0, x20                                       
000381b8  cdeb0094  bl        #0x730ec                                       ; _objc_release
000381bc  e00313aa  mov       x0, x19                                       
000381c0  fd7b42a9  ldp       x29, x30, [sp, #0x20]                         
000381c4  f44f41a9  ldp       x20, x19, [sp, #0x10]                         
000381c8  f657c3a8  ldp       x22, x21, [sp], #0x30                         
000381cc  ff2303d5  autibsp                                                 
000381d0  d0071eca  eor       x16, x30, x30, lsl #1                         
000381d4  5000f0b6  tbz       x16, #0x3e, #0x381dc                          
000381d8  208e38d4  brk       #0xc471                                       
000381dc  c4eb0014  b         #0x730ec                                       ; _objc_release

; IMAGE 01-mangoos.dylib UNSLID FUNCTION 0x381e0
000381e0  7f2303d5  pacibsp                                                 
000381e4  f657bda9  stp       x22, x21, [sp, #-0x30]!                       
000381e8  f44f01a9  stp       x20, x19, [sp, #0x10]                         
000381ec  fd7b02a9  stp       x29, x30, [sp, #0x20]                         
000381f0  fd830091  add       x29, sp, #0x20                                
000381f4  f40303aa  mov       x20, x3                                       
000381f8  f60301aa  mov       x22, x1                                       
000381fc  f50300aa  mov       x21, x0                                       
00038200  e00302aa  mov       x0, x2                                        
00038204  beeb0094  bl        #0x730fc                                       ; _objc_retain
00038208  f30300aa  mov       x19, x0                                       
0003820c  e00314aa  mov       x0, x20                                       
00038210  bbeb0094  bl        #0x730fc                                       ; _objc_retain
00038214  f40300aa  mov       x20, x0                                       
00038218  dc070094  bl        #0x3a188                                       ; sub_0x3a188
0003821c  a0000034  cbz       w0, #0x38230                                  
00038220  e00315aa  mov       x0, x21                                       
00038224  a2008052  mov       w2, #5                                        
00038228  9e040194  bl        #0x794a0                                       ; objc_msgSend$setState:
0003822c  08000014  b         #0x3824c                                       ; sub_0x3824c
00038230  480300f0  adrp      x8, #0xa3000                                  
00038234  088145f9  ldr       x8, [x8, #0xb00]                              
00038238  e00315aa  mov       x0, x21                                       
0003823c  e10316aa  mov       x1, x22                                       
00038240  e20313aa  mov       x2, x19                                       
00038244  e30314aa  mov       x3, x20                                       
00038248  1f093fd6  blraaz    x8                                            
0003824c  e00314aa  mov       x0, x20                                       
00038250  a7eb0094  bl        #0x730ec                                       ; _objc_release
00038254  e00313aa  mov       x0, x19                                       
00038258  fd7b42a9  ldp       x29, x30, [sp, #0x20]                         
0003825c  f44f41a9  ldp       x20, x19, [sp, #0x10]                         
00038260  f657c3a8  ldp       x22, x21, [sp], #0x30                         
00038264  ff2303d5  autibsp                                                 
00038268  d0071eca  eor       x16, x30, x30, lsl #1                         
0003826c  5000f0b6  tbz       x16, #0x3e, #0x38274                          
00038270  208e38d4  brk       #0xc471                                       
00038274  9eeb0014  b         #0x730ec                                       ; _objc_release

; IMAGE 01-mangoos.dylib UNSLID FUNCTION 0x38278
00038278  7f2303d5  pacibsp                                                 
0003827c  f657bda9  stp       x22, x21, [sp, #-0x30]!                       
00038280  f44f01a9  stp       x20, x19, [sp, #0x10]                         
00038284  fd7b02a9  stp       x29, x30, [sp, #0x20]                         
00038288  fd830091  add       x29, sp, #0x20                                
0003828c  f40303aa  mov       x20, x3                                       
00038290  f60301aa  mov       x22, x1                                       
00038294  f50300aa  mov       x21, x0                                       
00038298  e00302aa  mov       x0, x2                                        
0003829c  98eb0094  bl        #0x730fc                                       ; _objc_retain
000382a0  f30300aa  mov       x19, x0                                       
000382a4  e00314aa  mov       x0, x20                                       
000382a8  95eb0094  bl        #0x730fc                                       ; _objc_retain
000382ac  f40300aa  mov       x20, x0                                       
000382b0  b6070094  bl        #0x3a188                                       ; sub_0x3a188
000382b4  a0000034  cbz       w0, #0x382c8                                  
000382b8  e00315aa  mov       x0, x21                                       
000382bc  a2008052  mov       w2, #5                                        
000382c0  78040194  bl        #0x794a0                                       ; objc_msgSend$setState:
000382c4  08000014  b         #0x382e4                                       ; sub_0x382e4
000382c8  480300f0  adrp      x8, #0xa3000                                  
000382cc  088545f9  ldr       x8, [x8, #0xb08]                              
000382d0  e00315aa  mov       x0, x21                                       
000382d4  e10316aa  mov       x1, x22                                       
000382d8  e20313aa  mov       x2, x19                                       
000382dc  e30314aa  mov       x3, x20                                       
000382e0  1f093fd6  blraaz    x8                                            
000382e4  e00314aa  mov       x0, x20                                       
000382e8  81eb0094  bl        #0x730ec                                       ; _objc_release
000382ec  e00313aa  mov       x0, x19                                       
000382f0  fd7b42a9  ldp       x29, x30, [sp, #0x20]                         
000382f4  f44f41a9  ldp       x20, x19, [sp, #0x10]                         
000382f8  f657c3a8  ldp       x22, x21, [sp], #0x30                         
000382fc  ff2303d5  autibsp                                                 
00038300  d0071eca  eor       x16, x30, x30, lsl #1                         
00038304  5000f0b6  tbz       x16, #0x3e, #0x3830c                          
00038308  208e38d4  brk       #0xc471                                       
0003830c  78eb0014  b         #0x730ec                                       ; _objc_release

; IMAGE 01-mangoos.dylib UNSLID FUNCTION 0x38310
00038310  7f2303d5  pacibsp                                                 
00038314  fd7bbfa9  stp       x29, x30, [sp, #-0x10]!                       
00038318  fd030091  mov       x29, sp                                       
0003831c  200200f0  adrp      x0, #0x7f000                                  
00038320  00000991  add       x0, x0, #0x240                                 ; STR 'go.mangoos/mediavolume.touch'
00038324  410300d0  adrp      x1, #0xa2000                                  
00038328  21e03f91  add       x1, x1, #0xff8                                
0003832c  0ceb0094  bl        #0x72f5c                                       ; _notify_register_check
00038330  80000034  cbz       w0, #0x38340                                  
00038334  480300d0  adrp      x8, #0xa2000                                  
00038338  09008012  mov       w9, #-1                                       
0003833c  09f90fb9  str       w9, [x8, #0xff8]                              
00038340  fd7bc1a8  ldp       x29, x30, [sp], #0x10                         
00038344  ff0f5fd6  retab                                                   

; IMAGE 01-mangoos.dylib UNSLID FUNCTION 0x3a188
0003a188  7f2303d5  pacibsp                                                 
0003a18c  ff8300d1  sub       sp, sp, #0x20                                 
0003a190  fd7b01a9  stp       x29, x30, [sp, #0x10]                         
0003a194  fd430091  add       x29, sp, #0x10                                
0003a198  480300b0  adrp      x8, #0xa3000                                  
0003a19c  088d45f9  ldr       x8, [x8, #0xb18]                              
0003a1a0  1f0500b1  cmn       x8, #1                                        
0003a1a4  a1020054  b.ne      #0x3a1f8                                      
0003a1a8  48030090  adrp      x8, #0xa2000                                  
0003a1ac  00f94fb9  ldr       w0, [x8, #0xff8]                              
0003a1b0  1f040031  cmn       w0, #1                                        
0003a1b4  a0010054  b.eq      #0x3a1e8                                      
0003a1b8  ff0700f9  str       xzr, [sp, #8]                                 
0003a1bc  e1230091  add       x1, sp, #8                                    
0003a1c0  5fe30094  bl        #0x72f3c                                       ; _notify_get_state
0003a1c4  e80740f9  ldr       x8, [sp, #8]                                  
0003a1c8  080100b4  cbz       x8, #0x3a1e8                                  
0003a1cc  000080d2  mov       x0, #0                                        
0003a1d0  4fe40094  bl        #0x7330c                                       ; _time
0003a1d4  e80740f9  ldr       x8, [sp, #8]                                  
0003a1d8  080008eb  subs      x8, x0, x8                                    
0003a1dc  00a946fa  ccmp      x8, #6, #0, ge                                
0003a1e0  e0a79f1a  cset      w0, lt                                        
0003a1e4  02000014  b         #0x3a1ec                                       ; sub_0x3a1ec
0003a1e8  00008052  mov       w0, #0                                        
0003a1ec  fd7b41a9  ldp       x29, x30, [sp, #0x10]                         
0003a1f0  ff830091  add       sp, sp, #0x20                                 
0003a1f4  ff0f5fd6  retab                                                   
0003a1f8  400300b0  adrp      x0, #0xa3000                                  
0003a1fc  00602c91  add       x0, x0, #0xb18                                
0003a200  a10200f0  adrp      x1, #0x91000                                  
0003a204  21400e91  add       x1, x1, #0x390                                 ; __NSConcreteGlobalBlock
0003a208  b9e20094  bl        #0x72cec                                       ; _dispatch_once
0003a20c  e7ffff17  b         #0x3a1a8                                       ; sub_0x3a1a8

; IMAGE 01-mangoos.dylib UNSLID FUNCTION 0x49334
00049334  7f2303d5  pacibsp                                                 
00049338  fc6fbaa9  stp       x28, x27, [sp, #-0x60]!                       
0004933c  fa6701a9  stp       x26, x25, [sp, #0x10]                         
00049340  f85f02a9  stp       x24, x23, [sp, #0x20]                         
00049344  f65703a9  stp       x22, x21, [sp, #0x30]                         
00049348  f44f04a9  stp       x20, x19, [sp, #0x40]                         
0004934c  fd7b05a9  stp       x29, x30, [sp, #0x50]                         
00049350  fd430191  add       x29, sp, #0x50                                
00049354  ff8306d1  sub       sp, sp, #0x1a0                                
00049358  280200f0  adrp      x8, #0x90000                                  
0004935c  08e943f9  ldr       x8, [x8, #0x7d0]                               ; ___stack_chk_guard
00049360  080140f9  ldr       x8, [x8]                                      
00049364  a8031af8  stur      x8, [x29, #-0x60]                             
00049368  40008052  mov       w0, #2                                        
0004936c  01028052  mov       w1, #0x10                                     
00049370  22008052  mov       w2, #1                                        
00049374  03008052  mov       w3, #0                                        
00049378  1ea30094  bl        #0x71ff0                                       ; sub_0x71ff0
0004937c  e0000034  cbz       w0, #0x49398                                  
00049380  b3a60094  bl        #0x72e4c                                       ; _getprogname
00049384  a00000b4  cbz       x0, #0x49398                                  
00049388  a10100d0  adrp      x1, #0x7f000                                  
0004938c  21fc3691  add       x1, x1, #0xdbf                                 ; STR 'SpringBoard'
00049390  c3a70094  bl        #0x7329c                                       ; _strcmp
00049394  e0010034  cbz       w0, #0x493d0                                  
00049398  a8035af8  ldur      x8, [x29, #-0x60]                             
0004939c  290200f0  adrp      x9, #0x90000                                  
000493a0  29e943f9  ldr       x9, [x9, #0x7d0]                               ; ___stack_chk_guard
000493a4  290140f9  ldr       x9, [x9]                                      
000493a8  3f0108eb  cmp       x9, x8                                        
000493ac  e1200054  b.ne      #0x497c8                                      
000493b0  ff830691  add       sp, sp, #0x1a0                                
000493b4  fd7b45a9  ldp       x29, x30, [sp, #0x50]                         
000493b8  f44f44a9  ldp       x20, x19, [sp, #0x40]                         
000493bc  f65743a9  ldp       x22, x21, [sp, #0x30]                         
000493c0  f85f42a9  ldp       x24, x23, [sp, #0x20]                         
000493c4  fa6741a9  ldp       x26, x25, [sp, #0x10]                         
000493c8  fc6fc6a8  ldp       x28, x27, [sp], #0x60                         
000493cc  ff0f5fd6  retab                                                   
000493d0  00e4006f  movi      v0.2d, #0000000000000000                      
000493d4  e08303ad  stp       q0, q0, [sp, #0x70]                           
000493d8  e08302ad  stp       q0, q0, [sp, #0x50]                           
000493dc  80020090  adrp      x0, #0x99000                                  
000493e0  00001f91  add       x0, x0, #0x7c0                                 ; _OBJC_CLASS_$_NSConstantArray
000493e4  e2430191  add       x2, sp, #0x50                                 
000493e8  a38303d1  sub       x3, x29, #0xe0                                
000493ec  04028052  mov       w4, #0x10                                     
000493f0  fcac0094  bl        #0x747e0                                       ; objc_msgSend$countByEnumeratingWithState:objects:count:
000493f4  dc020090  adrp      x28, #0xa1000                                 
000493f8  e00500b4  cbz       x0, #0x494b4                                  
000493fc  f40300aa  mov       x20, x0                                       
00049400  e83340f9  ldr       x8, [sp, #0x60]                               
00049404  190140f9  ldr       x25, [x8]                                     
00049408  93020090  adrp      x19, #0x99000                                 
0004940c  73021f91  add       x19, x19, #0x7c0                               ; _OBJC_CLASS_$_NSConstantArray
00049410  da0200d0  adrp      x26, #0xa3000                                 
00049414  750200b0  adrp      x21, #0x96000                                 
00049418  b5022791  add       x21, x21, #0x9c0                               ; CFSTR '[Island] hooked %@'
0004941c  1b0080d2  mov       x27, #0                                       
00049420  965344f9  ldr       x22, [x28, #0x8a0]                             ; SEL layoutSubviews
00049424  e83340f9  ldr       x8, [sp, #0x60]                               
00049428  080140f9  ldr       x8, [x8]                                      
0004942c  1f0119eb  cmp       x8, x25                                       
00049430  60000054  b.eq      #0x4943c                                      
00049434  e00313aa  mov       x0, x19                                       
00049438  fda60094  bl        #0x7302c                                       ; _objc_enumerationMutation
0004943c  e82f40f9  ldr       x8, [sp, #0x58]                               
00049440  17797bf8  ldr       x23, [x8, x27, lsl #3]                        
00049444  e00317aa  mov       x0, x23                                       
00049448  89a50094  bl        #0x72a6c                                       ; _NSClassFromString
0004944c  000200b4  cbz       x0, #0x4948c                                  
00049450  e10316aa  mov       x1, x22                                       
00049454  fea50094  bl        #0x72c4c                                       ; _class_getInstanceMethod
00049458  a00100b4  cbz       x0, #0x4948c                                  
0004945c  f80300aa  mov       x24, x0                                       
00049460  9fa60094  bl        #0x72edc                                       ; _method_getImplementation
00049464  40db07f9  str       x0, [x26, #0xfb0]                             
00049468  10000090  adrp      x16, #0x49000                                 
0004946c  10321f91  add       x16, x16, #0x7cc                              
00049470  f023c1da  paciza    x16                                           
00049474  e10310aa  mov       x1, x16                                       
00049478  e00318aa  mov       x0, x24                                       
0004947c  a4a60094  bl        #0x72f0c                                       ; _method_setImplementation
00049480  f70300f9  str       x23, [sp]                                     
00049484  e00315aa  mov       x0, x21                                       
00049488  3d870094  bl        #0x6b17c                                       ; sub_0x6b17c
0004948c  7b070091  add       x27, x27, #1                                  
00049490  9f021beb  cmp       x20, x27                                      
00049494  81fcff54  b.ne      #0x49424                                      
00049498  e2430191  add       x2, sp, #0x50                                 
0004949c  a38303d1  sub       x3, x29, #0xe0                                
000494a0  e00313aa  mov       x0, x19                                       
000494a4  04028052  mov       w4, #0x10                                     
000494a8  ceac0094  bl        #0x747e0                                       ; objc_msgSend$countByEnumeratingWithState:objects:count:
000494ac  f40300aa  mov       x20, x0                                       
000494b0  60fbffb5  cbnz      x0, #0x4941c                                  
000494b4  00e4006f  movi      v0.2d, #0000000000000000                      
000494b8  e08301ad  stp       q0, q0, [sp, #0x30]                           
000494bc  e08300ad  stp       q0, q0, [sp, #0x10]                           
000494c0  80020090  adrp      x0, #0x99000                                  
000494c4  00601f91  add       x0, x0, #0x7d8                                 ; _OBJC_CLASS_$_NSConstantArray
000494c8  e2430091  add       x2, sp, #0x10                                 
000494cc  e3430291  add       x3, sp, #0x90                                 
000494d0  04028052  mov       w4, #0x10                                     
000494d4  c3ac0094  bl        #0x747e0                                       ; objc_msgSend$countByEnumeratingWithState:objects:count:
000494d8  c00700b4  cbz       x0, #0x495d0                                  
000494dc  f30300aa  mov       x19, x0                                       
000494e0  e81340f9  ldr       x8, [sp, #0x20]                               
000494e4  94020090  adrp      x20, #0x99000                                 
000494e8  94621f91  add       x20, x20, #0x7d8                               ; _OBJC_CLASS_$_NSConstantArray
000494ec  160140f9  ldr       x22, [x8]                                     
000494f0  d50200d0  adrp      x21, #0xa3000                                 
000494f4  b5e23e91  add       x21, x21, #0xfb8                              
000494f8  d70200d0  adrp      x23, #0xa3000                                 
000494fc  f7023f91  add       x23, x23, #0xfc0                              
00049500  180080d2  mov       x24, #0                                       
00049504  c8020090  adrp      x8, #0xa1000                                  
00049508  199145f9  ldr       x25, [x8, #0xb20]                              ; SEL setLayoutMode:reason:
0004950c  c8020090  adrp      x8, #0xa1000                                  
00049510  1a9545f9  ldr       x26, [x8, #0xb28]                              ; SEL preferredEdgeOutsetsForLayoutMode:suggestedOutsets:maximumOutsets:
00049514  e81340f9  ldr       x8, [sp, #0x20]                               
00049518  080140f9  ldr       x8, [x8]                                      
0004951c  1f0116eb  cmp       x8, x22                                       
00049520  60000054  b.eq      #0x4952c                                      
00049524  e00314aa  mov       x0, x20                                       
00049528  c1a60094  bl        #0x7302c                                       ; _objc_enumerationMutation
0004952c  e80f40f9  ldr       x8, [sp, #0x18]                               
00049530  1b7978f8  ldr       x27, [x8, x24, lsl #3]                        
00049534  e0031baa  mov       x0, x27                                       
00049538  4da50094  bl        #0x72a6c                                       ; _NSClassFromString
0004953c  600300b4  cbz       x0, #0x495a8                                  
00049540  fc0300aa  mov       x28, x0                                       
00049544  100000b0  adrp      x16, #0x4a000                                 
00049548  10021a91  add       x16, x16, #0x680                              
0004954c  f023c1da  paciza    x16                                           
00049550  e20310aa  mov       x2, x16                                       
00049554  e10319aa  mov       x1, x25                                       
00049558  e30315aa  mov       x3, x21                                       
0004955c  03040094  bl        #0x4a568                                       ; sub_0x4a568
00049560  a0000034  cbz       w0, #0x49574                                  
00049564  fb0300f9  str       x27, [sp]                                     
00049568  600200b0  adrp      x0, #0x96000                                  
0004956c  00002891  add       x0, x0, #0xa00                                 ; CFSTR '[Island] hooked %@ setLayoutMode:reason:'
00049570  03870094  bl        #0x6b17c                                       ; sub_0x6b17c
00049574  100000b0  adrp      x16, #0x4a000                                 
00049578  10821e91  add       x16, x16, #0x7a0                              
0004957c  f023c1da  paciza    x16                                           
00049580  e20310aa  mov       x2, x16                                       
00049584  e0031caa  mov       x0, x28                                       
00049588  e1031aaa  mov       x1, x26                                       
0004958c  e30317aa  mov       x3, x23                                       
00049590  f6030094  bl        #0x4a568                                       ; sub_0x4a568
00049594  a0000034  cbz       w0, #0x495a8                                  
00049598  fb0300f9  str       x27, [sp]                                     
0004959c  600200b0  adrp      x0, #0x96000                                  
000495a0  00802891  add       x0, x0, #0xa20                                 ; CFSTR '[Island] hooked %@ preferredEdgeOutsetsForLayoutMode:'
000495a4  f6860094  bl        #0x6b17c                                       ; sub_0x6b17c
000495a8  18070091  add       x24, x24, #1                                  
000495ac  7f0218eb  cmp       x19, x24                                      
000495b0  21fbff54  b.ne      #0x49514                                      
000495b4  e2430091  add       x2, sp, #0x10                                 
000495b8  e3430291  add       x3, sp, #0x90                                 
000495bc  e00314aa  mov       x0, x20                                       
000495c0  04028052  mov       w4, #0x10                                     
000495c4  87ac0094  bl        #0x747e0                                       ; objc_msgSend$countByEnumeratingWithState:objects:count:
000495c8  f30300aa  mov       x19, x0                                       
000495cc  a0f9ffb5  cbnz      x0, #0x49500                                  
000495d0  600200b0  adrp      x0, #0x96000                                  
000495d4  00002991  add       x0, x0, #0xa40                                 ; CFSTR '_SBGainMapView'
000495d8  25a50094  bl        #0x72a6c                                       ; _NSClassFromString
000495dc  d5020090  adrp      x21, #0xa1000                                 
000495e0  b40200f0  adrp      x20, #0xa0000                                 
000495e4  d6020090  adrp      x22, #0xa1000                                 
000495e8  000500b4  cbz       x0, #0x49688                                  
000495ec  f30300aa  mov       x19, x0                                       
000495f0  a14e44f9  ldr       x1, [x21, #0x898]                              ; SEL didMoveToWindow
000495f4  c30200d0  adrp      x3, #0xa3000                                  
000495f8  63203f91  add       x3, x3, #0xfc8                                
000495fc  100000b0  adrp      x16, #0x4a000                                 
00049600  10e22391  add       x16, x16, #0x8f8                              
00049604  f023c1da  paciza    x16                                           
00049608  e20310aa  mov       x2, x16                                       
0004960c  d7030094  bl        #0x4a568                                       ; sub_0x4a568
00049610  80000034  cbz       w0, #0x49620                                  
00049614  600200b0  adrp      x0, #0x96000                                  
00049618  00802991  add       x0, x0, #0xa60                                 ; CFSTR '[Island] hooked _SBGainMapView didMoveToWindow'
0004961c  d8860094  bl        #0x6b17c                                       ; sub_0x6b17c
00049620  c15244f9  ldr       x1, [x22, #0x8a0]                              ; SEL layoutSubviews
00049624  c30200d0  adrp      x3, #0xa3000                                  
00049628  63403f91  add       x3, x3, #0xfd0                                
0004962c  100000b0  adrp      x16, #0x4a000                                 
00049630  10522791  add       x16, x16, #0x9d4                              
00049634  f023c1da  paciza    x16                                           
00049638  e20310aa  mov       x2, x16                                       
0004963c  e00313aa  mov       x0, x19                                       
00049640  ca030094  bl        #0x4a568                                       ; sub_0x4a568
00049644  80000034  cbz       w0, #0x49654                                  
00049648  600200b0  adrp      x0, #0x96000                                  
0004964c  00002a91  add       x0, x0, #0xa80                                 ; CFSTR '[Island] hooked _SBGainMapView layoutSubviews'
00049650  cb860094  bl        #0x6b17c                                       ; sub_0x6b17c
00049654  816e46f9  ldr       x1, [x20, #0xcd8]                              ; SEL setHidden:
00049658  c30200d0  adrp      x3, #0xa3000                                  
0004965c  63603f91  add       x3, x3, #0xfd8                                
00049660  100000b0  adrp      x16, #0x4a000                                 
00049664  10822991  add       x16, x16, #0xa60                              
00049668  f023c1da  paciza    x16                                           
0004966c  e20310aa  mov       x2, x16                                       
00049670  e00313aa  mov       x0, x19                                       
00049674  bd030094  bl        #0x4a568                                       ; sub_0x4a568
00049678  80000034  cbz       w0, #0x49688                                  
0004967c  600200b0  adrp      x0, #0x96000                                  
00049680  00802a91  add       x0, x0, #0xaa0                                 ; CFSTR '[Island] hooked _SBGainMapView setHidden:'
00049684  be860094  bl        #0x6b17c                                       ; sub_0x6b17c
00049688  600200b0  adrp      x0, #0x96000                                  
0004968c  00002b91  add       x0, x0, #0xac0                                 ; CFSTR '_SBSystemApertureMagiciansCurtainView'
00049690  f7a40094  bl        #0x72a6c                                       ; _NSClassFromString
00049694  600300b4  cbz       x0, #0x49700                                  
00049698  f30300aa  mov       x19, x0                                       
0004969c  a14e44f9  ldr       x1, [x21, #0x898]                              ; SEL didMoveToWindow
000496a0  c30200d0  adrp      x3, #0xa3000                                  
000496a4  63803f91  add       x3, x3, #0xfe0                                
000496a8  100000b0  adrp      x16, #0x4a000                                 
000496ac  10b22c91  add       x16, x16, #0xb2c                              
000496b0  f023c1da  paciza    x16                                           
000496b4  e20310aa  mov       x2, x16                                       
000496b8  ac030094  bl        #0x4a568                                       ; sub_0x4a568
000496bc  80000034  cbz       w0, #0x496cc                                  
000496c0  600200b0  adrp      x0, #0x96000                                  
000496c4  00802b91  add       x0, x0, #0xae0                                 ; CFSTR '[Island] hooked _SBSystemApertureMagiciansCurtainView didMoveToWindow'
000496c8  ad860094  bl        #0x6b17c                                       ; sub_0x6b17c
000496cc  816e46f9  ldr       x1, [x20, #0xcd8]                              ; SEL setHidden:
000496d0  c30200d0  adrp      x3, #0xa3000                                  
000496d4  63a03f91  add       x3, x3, #0xfe8                                
000496d8  100000b0  adrp      x16, #0x4a000                                 
000496dc  10922e91  add       x16, x16, #0xba4                              
000496e0  f023c1da  paciza    x16                                           
000496e4  e20310aa  mov       x2, x16                                       
000496e8  e00313aa  mov       x0, x19                                       
000496ec  9f030094  bl        #0x4a568                                       ; sub_0x4a568
000496f0  80000034  cbz       w0, #0x49700                                  
000496f4  600200b0  adrp      x0, #0x96000                                  
000496f8  00002c91  add       x0, x0, #0xb00                                 ; CFSTR '[Island] hooked _SBSystemApertureMagiciansCurtainView setHidden:'
000496fc  a0860094  bl        #0x6b17c                                       ; sub_0x6b17c
00049700  600200b0  adrp      x0, #0x96000                                  
00049704  00802c91  add       x0, x0, #0xb20                                 ; CFSTR 'SBFTouchPassThroughView'
00049708  d9a40094  bl        #0x72a6c                                       ; _NSClassFromString
0004970c  a00100b4  cbz       x0, #0x49740                                  
00049710  c15244f9  ldr       x1, [x22, #0x8a0]                              ; SEL layoutSubviews
00049714  c30200d0  adrp      x3, #0xa3000                                  
00049718  63c03f91  add       x3, x3, #0xff0                                
0004971c  100000b0  adrp      x16, #0x4a000                                 
00049720  10c23091  add       x16, x16, #0xc30                              
00049724  f023c1da  paciza    x16                                           
00049728  e20310aa  mov       x2, x16                                       
0004972c  8f030094  bl        #0x4a568                                       ; sub_0x4a568
00049730  80000034  cbz       w0, #0x49740                                  
00049734  600200b0  adrp      x0, #0x96000                                  
00049738  00002d91  add       x0, x0, #0xb40                                 ; CFSTR '[Island] hooked SBFTouchPassThroughView layoutSubviews'
0004973c  90860094  bl        #0x6b17c                                       ; sub_0x6b17c
00049740  600200b0  adrp      x0, #0x96000                                  
00049744  00802d91  add       x0, x0, #0xb60                                 ; CFSTR 'SBSystemApertureViewController'
00049748  c9a40094  bl        #0x72a6c                                       ; _NSClassFromString
0004974c  c00100b4  cbz       x0, #0x49784                                  
00049750  c8020090  adrp      x8, #0xa1000                                  
00049754  016544f9  ldr       x1, [x8, #0x8c8]                               ; SEL viewWillAppear:
00049758  c30200d0  adrp      x3, #0xa3000                                  
0004975c  63e03f91  add       x3, x3, #0xff8                                
00049760  100000b0  adrp      x16, #0x4a000                                 
00049764  10023591  add       x16, x16, #0xd40                              
00049768  f023c1da  paciza    x16                                           
0004976c  e20310aa  mov       x2, x16                                       
00049770  7e030094  bl        #0x4a568                                       ; sub_0x4a568
00049774  80000034  cbz       w0, #0x49784                                  
00049778  600200b0  adrp      x0, #0x96000                                  
0004977c  00002e91  add       x0, x0, #0xb80                                 ; CFSTR '[Island] hooked SBSystemApertureViewController viewWillAppear:'
00049780  7f860094  bl        #0x6b17c                                       ; sub_0x6b17c
00049784  600200b0  adrp      x0, #0x96000                                  
00049788  00802e91  add       x0, x0, #0xba0                                 ; CFSTR 'SBSystemApertureWindow'
0004978c  b8a40094  bl        #0x72a6c                                       ; _NSClassFromString
00049790  40e0ffb4  cbz       x0, #0x49398                                  
00049794  c15244f9  ldr       x1, [x22, #0x8a0]                              ; SEL layoutSubviews
00049798  c30200f0  adrp      x3, #0xa4000                                  
0004979c  63000091  add       x3, x3, #0                                    
000497a0  100000b0  adrp      x16, #0x4a000                                 
000497a4  10e23591  add       x16, x16, #0xd78                              
000497a8  f023c1da  paciza    x16                                           
000497ac  e20310aa  mov       x2, x16                                       
000497b0  6e030094  bl        #0x4a568                                       ; sub_0x4a568
000497b4  20dfff34  cbz       w0, #0x49398                                  
000497b8  600200b0  adrp      x0, #0x96000                                  
000497bc  00002f91  add       x0, x0, #0xbc0                                 ; CFSTR '[Island] hooked SBSystemApertureWindow layoutSubviews'
000497c0  6f860094  bl        #0x6b17c                                       ; sub_0x6b17c
000497c4  f5feff17  b         #0x49398                                       ; sub_0x49398
000497c8  f1a40094  bl        #0x72b8c                                       ; ___stack_chk_fail

; IMAGE 01-mangoos.dylib UNSLID FUNCTION 0x4ad78
0004ad78  7f2303d5  pacibsp                                                 
0004ad7c  ff4305d1  sub       sp, sp, #0x150                                
0004ad80  ef3b0c6d  stp       d15, d14, [sp, #0xc0]                         
0004ad84  ed330d6d  stp       d13, d12, [sp, #0xd0]                         
0004ad88  eb2b0e6d  stp       d11, d10, [sp, #0xe0]                         
0004ad8c  e9230f6d  stp       d9, d8, [sp, #0xf0]                           
0004ad90  fa6710a9  stp       x26, x25, [sp, #0x100]                        
0004ad94  f85f11a9  stp       x24, x23, [sp, #0x110]                        
0004ad98  f65712a9  stp       x22, x21, [sp, #0x120]                        
0004ad9c  f44f13a9  stp       x20, x19, [sp, #0x130]                        
0004ada0  fd7b14a9  stp       x29, x30, [sp, #0x140]                        
0004ada4  fd030591  add       x29, sp, #0x140                               
0004ada8  f40301aa  mov       x20, x1                                       
0004adac  d4a00094  bl        #0x730fc                                       ; _objc_retain
0004adb0  f30300aa  mov       x19, x0                                       
0004adb4  c80200d0  adrp      x8, #0xa4000                                  
0004adb8  080140f9  ldr       x8, [x8]                                      
0004adbc  880000b4  cbz       x8, #0x4adcc                                  
0004adc0  e00313aa  mov       x0, x19                                       
0004adc4  e10314aa  mov       x1, x20                                       
0004adc8  1f093fd6  blraaz    x8                                            
0004adcc  9c000094  bl        #0x4b03c                                       ; sub_0x4b03c
0004add0  c80200d0  adrp      x8, #0xa4000                                  
0004add4  08414039  ldrb      w8, [x8, #0x10]                               
0004add8  c80f0034  cbz       w8, #0x4afd0                                  
0004addc  e00313aa  mov       x0, x19                                       
0004ade0  c7a00094  bl        #0x730fc                                       ; _objc_retain
0004ade4  f40300aa  mov       x20, x0                                       
0004ade8  d90200b0  adrp      x25, #0xa3000                                 
0004adec  204340fd  ldr       d0, [x25, #0x80]                              
0004adf0  01107e1e  fmov      d1, #-1.00000000                              
0004adf4  0028611e  fadd      d0, d0, d1                                    
0004adf8  00c0601e  fabs      d0, d0                                        
0004adfc  d60200d0  adrp      x22, #0xa4000                                 
0004ae00  c10e40fd  ldr       d1, [x22, #0x18]                              
0004ae04  2820601e  fcmp      d1, #0.0                                      
0004ae08  e8079f1a  cset      w8, ne                                        
0004ae0c  d70200d0  adrp      x23, #0xa4000                                 
0004ae10  e11240fd  ldr       d1, [x23, #0x20]                              
0004ae14  2820601e  fcmp      d1, #0.0                                      
0004ae18  18059f1a  csinc     w24, w8, wzr, eq                              
0004ae1c  a80100f0  adrp      x8, #0x81000                                  
0004ae20  01e143fd  ldr       d1, [x8, #0x7c0]                              
0004ae24  0020611e  fcmp      d0, d1                                        
0004ae28  00db407a  ccmp      w24, #0, #0, le                               
0004ae2c  e00c0054  b.eq      #0x4afc8                                      
0004ae30  0020611e  fcmp      d0, d1                                        
0004ae34  4d0a0054  b.le      #0x4af7c                                      
0004ae38  e00314aa  mov       x0, x20                                       
0004ae3c  f1ab0094  bl        #0x75e00                                       ; objc_msgSend$layer
0004ae40  fd031daa  mov       x29, x29                                      
0004ae44  baa00094  bl        #0x7312c                                       ; _objc_retainAutoreleasedReturnValue
0004ae48  f50300aa  mov       x21, x0                                       
0004ae4c  e00314aa  mov       x0, x20                                       
0004ae50  44a40094  bl        #0x73f60                                       ; objc_msgSend$bounds
0004ae54  a808e8d2  mov       x8, #0x4045000000000000                       
0004ae58  0001679e  fmov      d0, x8                                        
0004ae5c  0118631e  fdiv      d1, d0, d3                                    
0004ae60  02106e1e  fmov      d2, #1.00000000                               
0004ae64  6020621e  fcmp      d3, d2                                        
0004ae68  28cc601e  fcsel     d8, d1, d0, gt                                
0004ae6c  e00315aa  mov       x0, x21                                       
0004ae70  9ca20094  bl        #0x738e0                                       ; objc_msgSend$anchorPoint
0004ae74  20d4e87e  fabd      d0, d1, d8                                    
0004ae78  a80100f0  adrp      x8, #0x81000                                  
0004ae7c  096146fd  ldr       d9, [x8, #0xcc0]                              
0004ae80  0020691e  fcmp      d0, d9                                        
0004ae84  0c010054  b.gt      #0x4aea4                                      
0004ae88  e00315aa  mov       x0, x21                                       
0004ae8c  95a20094  bl        #0x738e0                                       ; objc_msgSend$anchorPoint
0004ae90  01107c1e  fmov      d1, #-0.50000000                              
0004ae94  0028611e  fadd      d0, d0, d1                                    
0004ae98  00c0601e  fabs      d0, d0                                        
0004ae9c  0020691e  fcmp      d0, d9                                        
0004aea0  4d030054  b.le      #0x4af08                                      
0004aea4  e00315aa  mov       x0, x21                                       
0004aea8  8ea20094  bl        #0x738e0                                       ; objc_msgSend$anchorPoint
0004aeac  0940601e  fmov      d9, d0                                        
0004aeb0  2a40601e  fmov      d10, d1                                       
0004aeb4  e00315aa  mov       x0, x21                                       
0004aeb8  baaf0094  bl        #0x76da0                                       ; objc_msgSend$position
0004aebc  0b40601e  fmov      d11, d0                                       
0004aec0  2c40601e  fmov      d12, d1                                       
0004aec4  e00314aa  mov       x0, x20                                       
0004aec8  26a40094  bl        #0x73f60                                       ; objc_msgSend$bounds
0004aecc  4d40601e  fmov      d13, d2                                       
0004aed0  e00314aa  mov       x0, x20                                       
0004aed4  23a40094  bl        #0x73f60                                       ; objc_msgSend$bounds
0004aed8  6e40601e  fmov      d14, d3                                       
0004aedc  0f106c1e  fmov      d15, #0.50000000                              
0004aee0  00106c1e  fmov      d0, #0.50000000                               
0004aee4  e00315aa  mov       x0, x21                                       
0004aee8  0141601e  fmov      d1, d8                                        
0004aeec  ddb20094  bl        #0x77a60                                       ; objc_msgSend$setAnchorPoint:
0004aef0  00396a1e  fsub      d0, d8, d10                                   
0004aef4  01304e1f  fmadd     d1, d0, d14, d12                              
0004aef8  e039691e  fsub      d0, d15, d9                                   
0004aefc  002c4d1f  fmadd     d0, d0, d13, d11                              
0004af00  e00315aa  mov       x0, x21                                       
0004af04  27b80094  bl        #0x78fa0                                       ; objc_msgSend$setPosition:
0004af08  204340fd  ldr       d0, [x25, #0x80]                              
0004af0c  e8430291  add       x8, sp, #0x90                                 
0004af10  0140601e  fmov      d1, d0                                        
0004af14  029e0094  bl        #0x7271c                                       ; _CGAffineTransformMakeScale
0004af18  b40000b4  cbz       x20, #0x4af2c                                 
0004af1c  e8830191  add       x8, sp, #0x60                                 
0004af20  e00314aa  mov       x0, x20                                       
0004af24  9fbe0094  bl        #0x7a9a0                                       ; objc_msgSend$transform
0004af28  04000014  b         #0x4af38                                       ; sub_0x4af38
0004af2c  00e4006f  movi      v0.2d, #0000000000000000                      
0004af30  e08303ad  stp       q0, q0, [sp, #0x70]                           
0004af34  e01b803d  str       q0, [sp, #0x60]                               
0004af38  e08744ad  ldp       q0, q1, [sp, #0x90]                           
0004af3c  e08701ad  stp       q0, q1, [sp, #0x30]                           
0004af40  e02fc03d  ldr       q0, [sp, #0xb0]                               
0004af44  e017803d  str       q0, [sp, #0x50]                               
0004af48  e0830191  add       x0, sp, #0x60                                 
0004af4c  e1c30091  add       x1, sp, #0x30                                 
0004af50  eb9d0094  bl        #0x726fc                                       ; _CGAffineTransformEqualToTransform
0004af54  00010037  tbnz      w0, #0, #0x4af74                              
0004af58  e08744ad  ldp       q0, q1, [sp, #0x90]                           
0004af5c  e00700ad  stp       q0, q1, [sp]                                  
0004af60  e02fc03d  ldr       q0, [sp, #0xb0]                               
0004af64  e00b803d  str       q0, [sp, #0x20]                               
0004af68  e2030091  mov       x2, sp                                        
0004af6c  e00314aa  mov       x0, x20                                       
0004af70  84ba0094  bl        #0x79980                                       ; objc_msgSend$setTransform:
0004af74  e00315aa  mov       x0, x21                                       
0004af78  5da00094  bl        #0x730ec                                       ; _objc_release
0004af7c  78020034  cbz       w24, #0x4afc8                                 
0004af80  e00314aa  mov       x0, x20                                       
0004af84  87a40094  bl        #0x741a0                                       ; objc_msgSend$center
0004af88  0340601e  fmov      d3, d0                                        
0004af8c  2240601e  fmov      d2, d1                                        
0004af90  c00e40fd  ldr       d0, [x22, #0x18]                              
0004af94  6028601e  fadd      d0, d3, d0                                    
0004af98  e11240fd  ldr       d1, [x23, #0x20]                              
0004af9c  4128611e  fadd      d1, d2, d1                                    
0004afa0  64d4e07e  fabd      d4, d3, d0                                    
0004afa4  a80100f0  adrp      x8, #0x81000                                  
0004afa8  032144fd  ldr       d3, [x8, #0x840]                              
0004afac  8020631e  fcmp      d4, d3                                        
0004afb0  8c000054  b.gt      #0x4afc0                                      
0004afb4  42d4e17e  fabd      d2, d2, d1                                    
0004afb8  4020631e  fcmp      d2, d3                                        
0004afbc  6d000054  b.le      #0x4afc8                                      
0004afc0  e00314aa  mov       x0, x20                                       
0004afc4  a7b30094  bl        #0x77e60                                       ; objc_msgSend$setCenter:
0004afc8  e00314aa  mov       x0, x20                                       
0004afcc  48a00094  bl        #0x730ec                                       ; _objc_release
0004afd0  e00313aa  mov       x0, x19                                       
0004afd4  46a00094  bl        #0x730ec                                       ; _objc_release
0004afd8  fd7b54a9  ldp       x29, x30, [sp, #0x140]                        
0004afdc  f44f53a9  ldp       x20, x19, [sp, #0x130]                        
0004afe0  f65752a9  ldp       x22, x21, [sp, #0x120]                        
0004afe4  f85f51a9  ldp       x24, x23, [sp, #0x110]                        
0004afe8  fa6750a9  ldp       x26, x25, [sp, #0x100]                        
0004afec  e9234f6d  ldp       d9, d8, [sp, #0xf0]                           
0004aff0  eb2b4e6d  ldp       d11, d10, [sp, #0xe0]                         
0004aff4  ed334d6d  ldp       d13, d12, [sp, #0xd0]                         
0004aff8  ef3b4c6d  ldp       d15, d14, [sp, #0xc0]                         
0004affc  ff430591  add       sp, sp, #0x150                                
0004b000  ff0f5fd6  retab                                                   
0004b004  08000014  b         #0x4b024                                       ; sub_0x4b024
0004b008  07000014  b         #0x4b024                                       ; sub_0x4b024
0004b00c  06000014  b         #0x4b024                                       ; sub_0x4b024
0004b010  05000014  b         #0x4b024                                       ; sub_0x4b024
0004b014  04000014  b         #0x4b024                                       ; sub_0x4b024
0004b018  03000014  b         #0x4b024                                       ; sub_0x4b024
0004b01c  02000014  b         #0x4b024                                       ; sub_0x4b024
0004b020  01000014  b         #0x4b024                                       ; sub_0x4b024
0004b024  3f040071  cmp       w1, #1                                        
0004b028  81000054  b.ne      #0x4b038                                      
0004b02c  f09f0094  bl        #0x72fec                                       ; _objc_begin_catch
0004b030  fb9f0094  bl        #0x7301c                                       ; _objc_end_catch
0004b034  e7ffff17  b         #0x4afd0                                       ; sub_0x4afd0
0004b038  c99e0094  bl        #0x72b5c                                       ; __Unwind_Resume
