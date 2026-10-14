package
{
   import flash.display.*;
   import flash.events.*;
   import flash.net.*;
   import flash.system.*;
   import flash.text.TextField;
   import flash.text.TextFormat;
   import flash.utils.ByteArray;
   import flash.utils.getDefinitionByName;
   import flash.utils.getTimer;
   

   import com.aqwapi.Api;
   import ui.ApiMenus;
   [SWF(width="960", height="550", backgroundColor="#000000", frameRate="30")]
   public class AirShell extends Sprite
   {
      
      public static var Game:Object;
      
      private var mode:String = "game";
      
      private var sURL:String = "https://" + mode + ".aq.com/game/";
      
      private var gameFile:String = "spider.swf";
      
      private var versionAPI:String = "api/data/gameversion";
      
      private var loaderVars:Object;
      
      private var sVersion:String;
      
      private var sTitle:String = "Spider Client";
      
      private var sBG:String = "";
      
      private var isEU:Boolean = false;
      
      private var versionLoader:URLLoader;
      
      private var swfFetch:URLLoader;
      
      private var swfLoader:Loader;
      
      private var titleDomain:ApplicationDomain;
      
      private var loginURL:String;
      private var bridge:Object;
      
      private var status:TextField;
      
      private var errors:String = "";
      
      private var t0:int;
      
      private var fgRate:Number = 0;
      
      private var devLoginT0:int = 0;
      
      public function AirShell()
      {
         super();
         if(stage)
         {
            init();
         }
         else
         {
            addEventListener("addedToStage",onAdded);
         }
      }
      
      private function onAppDeactivate(param1:Event) : void
      {
         if(fgRate == 0 && stage.frameRate > 4)
         {
            fgRate = stage.frameRate;
            stage.frameRate = 4;
         }
      }
      
      private function onAppActivate(param1:Event) : void
      {
         if(fgRate > 0)
         {
            stage.frameRate = fgRate;
            fgRate = 0;
         }
      }
      
      private function onAdded(param1:Event) : void
      {
         removeEventListener("addedToStage",onAdded);
         init();
      }
      
      private function init() : void
      {
         t0 = getTimer();

         try {
            var haxeBoot:* = getDefinitionByName("haxe");
            if (haxeBoot != null && haxeBoot.initSwc != null) {
               haxeBoot.initSwc(null);
            }
         } catch (e:Error) {}

         try {
            Api.ensureMathShims();
         } catch (e:Error) {}

         try {
            Api.preloadAssets();
         } catch (e:Error) {}

         try {
            Security.allowDomain("*");
            Security.allowInsecureDomain("*");
         } catch (e:Error) {}
         stage.scaleMode = "showAll";
         stage.align = "T";
         status = new TextField();
         status.defaultTextFormat = new TextFormat("_sans",15,14540253);
         status.x = 16;
         status.y = 12;
         status.width = 928;
         status.height = 300;
         status.multiline = true;
         status.wordWrap = true;
         status.selectable = false;
         status.mouseEnabled = false;
         stage.addChild(status);
         stage.addEventListener("keyDown",onKey);
         stage.addEventListener("deactivate",onAppDeactivate);
         stage.addEventListener("activate",onAppActivate);
         loaderInfo.uncaughtErrorEvents.addEventListener("uncaughtError",onUncaught);
         loginURL = sURL + "api/login/now";
         setStatus("shell started (" + Capabilities.os + ", " + Capabilities.version + ", sandbox " + Security.sandboxType + ", stage " + stage.stageWidth + "x" + stage.stageHeight + ")");
         GetVersion();
      }
      
      private function setStatus(param1:String) : void
      {
         var _loc2_:String = "[" + Math.round((getTimer() - t0) / 100) / 10 + "s] " + param1;
         if(status != null)
         {
            status.text = _loc2_ + errors;
         }
      }
      
      private function onKey(param1:KeyboardEvent) : void
      {
         if(param1.keyCode == 16777238)
         {
            param1.preventDefault();
         }
      }
      
      private function onUncaught(param1:UncaughtErrorEvent) : void
      {
         var _loc3_:Error = param1.error as Error;
         var _loc2_:String = _loc3_ != null ? _loc3_.name + ": " + _loc3_.message + "\n" + _loc3_.getStackTrace() : String(param1.error);
         if(status != null)
         {
            errors += "\nERROR: " + _loc2_;
            status.appendText("\nERROR: " + _loc2_);
         }
      }
      
      private function GetVersion() : void
      {
         setStatus("fetching " + sURL + versionAPI);
         versionLoader = new URLLoader();
         versionLoader.addEventListener("complete",onVersionComplete,false,0,true);
         versionLoader.addEventListener("ioError",onVersionError,false,0,true);
         versionLoader.addEventListener("securityError",onVersionError,false,0,true);
         versionLoader.load(new URLRequest(sURL + versionAPI + "?ver=" + Math.random()));
      }
      
      private function onVersionComplete(param1:Event) : void
      {
         var _loc2_:Object = JSON.parse(param1.target.data);
         loaderVars = _loc2_;
         gameFile = _loc2_.sFile;
         sVersion = _loc2_.sVersion;
         sTitle = _loc2_.sTitle;
         sBG = _loc2_.sBG;
         isEU = _loc2_.isEU == "true";
         versionLoader = null;
         LoadGame();
      }
      
      private function onVersionError(param1:Event) : void
      {
         setStatus("gameversion API failed (" + param1 + "), loading uncached");
         versionLoader = null;
         LoadGame();
      }
      
      private function LoadGame() : void
      {
         var _loc1_:String = sVersion ? sVersion : String(Math.random());
         titleDomain = new ApplicationDomain();
         swfFetch = new URLLoader();
         swfFetch.dataFormat = "binary";
         swfFetch.addEventListener("progress",onGameProgress,false,0,true);
         swfFetch.addEventListener("complete",onGameBytes,false,0,true);
         swfFetch.addEventListener("ioError",onGameError,false,0,true);
         swfFetch.addEventListener("securityError",onGameError,false,0,true);
         var _loc2_:String = Capabilities.isDebugger && false ? "" + ("".indexOf("?") > -1 ? "&" : "?") + "t=" + new Date().time : sURL + "gamefiles/" + gameFile + "?ver=" + _loc1_;
         setStatus("fetching " + _loc2_);
         var _loc3_:URLRequest = new URLRequest(_loc2_);
         swfFetch.load(_loc3_);
      }
      
      private function devLoginFrame(param1:Event) : void
      {
         var _loc2_:Object = null;
         if(devLoginT0 == 0)
         {
            devLoginT0 = getTimer();
         }
         if(getTimer() - devLoginT0 > 90000)
         {
            stage.removeEventListener("enterFrame",devLoginFrame);
            return;
         }
         try
         {
            _loc2_ = Game.mcLogin;
            if(_loc2_ == null || _loc2_.ni == null || _loc2_.pi == null || _loc2_.btnLogin == null || !_loc2_.btnLogin.visible || _loc2_.stage == null)
            {
               return;
            }
            stage.removeEventListener("enterFrame",devLoginFrame);
            _loc2_.ni.text = "";
            _loc2_.pi.text = "";
            _loc2_.btnLogin.dispatchEvent(new MouseEvent("click",true));
            setStatus("dev auto-login sent for ");
         }
         catch(err:Error)
         {
         }
      }
      
      private function onGameProgress(param1:ProgressEvent) : void
      {
         setStatus("fetching " + gameFile + " " + Math.round(param1.bytesLoaded / 1024) + " / " + Math.round(param1.bytesTotal / 1024) + " KB");
      }
      
      private function onGameBytes(param1:Event) : void
      {
         var _loc2_:ByteArray = swfFetch.data as ByteArray;
         setStatus("fetched " + (_loc2_ ? _loc2_.length : 0) + " bytes, importing");
         var _loc3_:LoaderContext = new LoaderContext(false,ApplicationDomain.currentDomain);
         _loc3_.allowCodeImport = true;
         swfLoader = new Loader();
         swfLoader.contentLoaderInfo.addEventListener("complete",onGameComplete,false,0,true);
         swfLoader.contentLoaderInfo.addEventListener("ioError",onGameError,false,0,true);
         swfLoader.loadBytes(_loc2_,_loc3_);
      }
      
      private function onGameComplete(param1:Event) : void
      {
         var bc:Class;
         var e:Event = param1;
         var content:DisplayObject = swfLoader.content;
         Game = Object(content).root;
         Game.params.sURL = sURL;
         Game.params.sTitle = sTitle;
         Game.params.vars = loaderVars;
         Game.params.isWeb = false;
         Game.params.doSignup = false;
         Game.params.isEU = isEU;
         Game.params.test = false;
         Game.params.loginURL = loginURL;
         Game.params.sBG = sBG;
         Game.params.sFilePath = sURL + "gamefiles/";
         if(Capabilities.isDebugger && "".indexOf("10.0.2.2") > -1)
         {
            Game.params.devHost = "10.0.2.2";
         }
         Game.titleDomain = titleDomain;
         stage.frameRate = swfLoader.contentLoaderInfo.frameRate;
         setStatus("game imported: swfVersion=" + swfLoader.contentLoaderInfo.swfVersion + " fps=" + stage.frameRate + " sFilePath=" + Game.params.sFilePath);
         content.x = 0;
         content.y = 0;
         if(Capabilities.isDebugger && bridge == null)
         {
            try
            {
               bc = getDefinitionByName("spiderloader.JudgeBridge") as Class;
               bridge = new bc(stage,function():*
               {
                  return content;
               });
            }
            catch(be:Error)
            {
            }
         }
         stage.addChildAt(content,0);

         // Initialize our mod after game loads
         initMod(Game);
         if(errors == "")
         {
            stage.removeChild(status);
            status = null;
         }
      }
      
      private function onGameError(param1:Event) : void
      {
         setStatus("game load failed: " + param1);
      }
   
      private function initMod(gameInstance:Object) : void
      {
         try
         {
            var apiClass:Class = getDefinitionByName("com.aqwapi.Api") as Class;
            if (apiClass != null && apiClass.init != null)
            {
               apiClass.init(Game);
            }
         }
         catch (e:Error)
         {
            trace("API init error: " + e);
         }

         try
         {
            var apiMenusClass:Class = getDefinitionByName("ui.ApiMenus") as Class;
            if (apiMenusClass != null && apiMenusClass.injectStandalone != null)
            {
               apiMenusClass.injectStandalone(stage);
            }
         }
         catch (e:Error)
         {
            trace("Menu inject error: " + e);
            if (status != null)
            {
               status.appendText("\nMenu inject error: " + e);
            }
         }
      }

   }
}
