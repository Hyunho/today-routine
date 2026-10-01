from pathlib import Path
import hashlib,json
objects={}
def ident(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def add(key,isa,**kw):
 i=ident(key); objects[i]={'isa':isa,**kw}; return i
def encode(x):
 if isinstance(x,dict): return '{ '+ ' '.join(f'{encode(k)} = {encode(v)};' for k,v in x.items())+' }'
 if isinstance(x,list): return '( '+', '.join(encode(v) for v in x)+' )'
 return json.dumps(str(x),ensure_ascii=False)
root=Path(__file__).resolve().parent.parent
appfiles=sorted(str(p.relative_to(root)) for p in (root/'TodayRoutine').rglob('*.swift'))
uifiles=sorted(str(p.relative_to(root)) for p in (root/'TodayRoutineUITests').rglob('*.swift'))
products=[]; filerefs=[]; targets=[]
projectid=ident('project'); appid=ident('TodayRoutine'); testsid=ident('TodayRoutineUITests')
for name,files,product,ptype in [('TodayRoutine',appfiles,'TodayRoutine.app','com.apple.product-type.application'),('TodayRoutineUITests',uifiles,'TodayRoutineUITests.xctest','com.apple.product-type.bundle.ui-testing')]:
 refs=[]
 for path in files:
  ref=add(path,'PBXFileReference',lastKnownFileType='sourcecode.swift',path=path,sourceTree='<group>'); filerefs.append(ref)
  refs.append(add('build:'+path,'PBXBuildFile',fileRef=ref))
 prod=add(product,'PBXFileReference',explicitFileType='wrapper.application' if name=='TodayRoutine' else 'wrapper.cfbundle',path=product,sourceTree='BUILT_PRODUCTS_DIR'); products.append(prod)
 src=add(name+'sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=refs,runOnlyForDeploymentPostprocessing=0)
 fw=add(name+'frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
 cfgs=[]
 for cfg in ['Debug','Release']:
  settings={'PRODUCT_NAME':'$(TARGET_NAME)','SWIFT_VERSION':'5.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','TARGETED_DEVICE_FAMILY':'1','GENERATE_INFOPLIST_FILE':'YES','CODE_SIGN_STYLE':'Automatic','PRODUCT_BUNDLE_IDENTIFIER':'com.hyunho.TodayRoutine'+('UITests' if name.endswith('UITests') else ''),'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if cfg=='Debug' else '-O','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if cfg=='Debug' else '', 'ENABLE_TESTABILITY':'YES','CURRENT_PROJECT_VERSION':'1','MARKETING_VERSION':'1.0','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks @loader_path/Frameworks'}
  if name=='TodayRoutine': settings.update({'INFOPLIST_KEY_CFBundleDisplayName':'오늘의 루틴','INFOPLIST_KEY_UILaunchScreen_Generation':'YES','INFOPLIST_KEY_UIApplicationSceneManifest_Generation':'YES','INFOPLIST_KEY_UISupportedInterfaceOrientations':'UIInterfaceOrientationPortrait'})
  else: settings['TEST_TARGET_NAME']='TodayRoutine'
  cfgs.append(add(name+cfg,'XCBuildConfiguration',buildSettings=settings,name=cfg))
 cfglist=add(name+'configs','XCConfigurationList',buildConfigurations=cfgs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
 deps=[]
 if name.endswith('UITests'):
  proxy=add('proxy','PBXContainerItemProxy',containerPortal=projectid,proxyType=1,remoteGlobalIDString=appid,remoteInfo='TodayRoutine')
  deps=[add('dep','PBXTargetDependency',target=appid,targetProxy=proxy)]
 targets.append(add(name,'PBXNativeTarget',buildConfigurationList=cfglist,buildPhases=[src,fw],buildRules=[],dependencies=deps,name=name,productName=name,productReference=prod,productType=ptype))
pg=add('products','PBXGroup',children=products,name='Products',sourceTree='<group>')
group=add('main','PBXGroup',children=filerefs+[pg],sourceTree='<group>')
pcfg=[add('project'+cfg,'XCBuildConfiguration',buildSettings={'CLANG_ENABLE_MODULES':'YES','SWIFT_VERSION':'5.0'},name=cfg) for cfg in ['Debug','Release']]
pcl=add('projectconfigs','XCConfigurationList',buildConfigurations=pcfg,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
add('project','PBXProject',attributes={'LastUpgradeCheck':'1600'},buildConfigurationList=pcl,compatibilityVersion='Xcode 14.0',developmentRegion='ko',knownRegions=['ko','en','Base'],mainGroup=group,productRefGroup=pg,projectDirPath='',projectRoot='',targets=targets)
out=root/'TodayRoutine.xcodeproj'; out.mkdir(exist_ok=True)
(out/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':projectid})+'\n')
scheme=out/'xcshareddata/xcschemes'; scheme.mkdir(parents=True,exist_ok=True)
def ref(i,n,b): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{i}" BuildableName="{b}" BlueprintName="{n}" ReferencedContainer="container:TodayRoutine.xcodeproj"/>'
a=ref(appid,'TodayRoutine','TodayRoutine.app'); t=ref(testsid,'TodayRoutineUITests','TodayRoutineUITests.xctest')
(scheme/'TodayRoutine.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{a}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{t}</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{a}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"><BuildableProductRunnable runnableDebuggingMode="0">{a}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print('Generated project:',len(appfiles),'Swift sources')
