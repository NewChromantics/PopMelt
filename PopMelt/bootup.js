Pop.Debug("Melttttttiiinnggg");

Pop.Include = function(Filename)
{
	const Source = Pop.LoadFileAsString(Filename);
	return Pop.CompileAndRun( Source, Filename );
}

//Pop.Include('PopEngineCommon/PromiseQueue.js');
Pop.Include('PopEngineCommon/PopApi.js');
Pop.Include('PopEngineCommon/PopShaderCache.js');
Pop.Include('PopEngineCommon/PopFrameCounter.js');
Pop.Include('PopEngineCommon/PopMath.js');
Pop.Include('PopEngineCommon/ParamsWindow.js');
Pop.Include('PopEngineCommon/PopCamera.js');

Pop.Include('AssetManager.js');

const SceneRenderShaderFilename = 'SceneTrace.frag.glsl';
const EnvironmentMapFilename = 'TestEnvMapEquirect.jpg';
const NoiseFilename = 'Noise.png';

const Window = new Pop.Opengl.Window("Melt");
Window.RenderCounter = new Pop.FrameCounter('fps');
Window.OnRender = GameRender;


Window.OnMouseMove = function(x,y,MouseButton)
{
	const Camera = UserCamera;

	if ( Camera && MouseButton == 0 )
	{
		Camera.OnCameraOrbit(x,y,0,false);
	}
	if ( Camera && MouseButton == 1 )
	{
		const ZoomScale = 10;
		Camera.OnCameraPanLocal(0,0,y*ZoomScale,false);
	}
}
Window.OnMouseDown = function(x,y,MouseButton)
{
	const Camera = UserCamera;

	if ( Camera && MouseButton == 0 )
	{
		Camera.OnCameraOrbit(x,y,0,true);
	}
	if ( Camera && MouseButton == 1 )
	{
		const ZoomScale = 10;
		Camera.OnCameraPanLocal(0,0,y*ZoomScale,true);
	}
}
Window.OnMouseScroll = function(x,y,Button,Delta)
{
	const Camera = UserCamera;

	if (Camera)
	{
		let Fly = Delta[1] * 50;
		//Fly *= Params.ScrollFlySpeed;
		Camera.OnCameraPanLocal( 0, 0, 0, true );
		Camera.OnCameraPanLocal( 0, 0, Fly, false );
	}
}


let Cameras = [];
let UserCamera = null;


const Params = {};
Params.ClearColour = [0.8,0.5,0.1];
Params.FovVertical = 45;
Params.RefractionScalar = 0.66;
Params.RefractionAberrationDelta = 0.01;
Params.MoonEdgeThickness = 0.2;
Params.MoonEdgeThicknessNoiseFreq = 1.0;
Params.MoonEdgeThicknessNoiseScale = 1.0;
Params.BouncePastEdge = 0.24;
Params.NormalViaRayStart = 0.001;
Params.TimeMult = 1.01;
Params.PlaneY = -10;
Params.ShowDepth = false;
Params.ShowDepthFar = 30;
Params.PassJitter = 0.001;
Params.FloorTileSize = 10;
Params.RenderEnvironmentSkybox = false;

const ParamsWindow = new Pop.ParamsWindow(Params,function(){});
ParamsWindow.AddParam('RefractionScalar',0,1);
ParamsWindow.AddParam('RefractionAberrationDelta',0,0.3);
ParamsWindow.AddParam('MoonEdgeThickness',0,1);
ParamsWindow.AddParam('MoonEdgeThicknessNoiseFreq',0,10);
ParamsWindow.AddParam('MoonEdgeThicknessNoiseScale',0,10);
ParamsWindow.AddParam('BouncePastEdge',0.001,1);
ParamsWindow.AddParam('NormalViaRayStart',0,1);
ParamsWindow.AddParam('TimeMult',0,5);
ParamsWindow.AddParam('PlaneY',-50,50);
ParamsWindow.AddParam('ShowDepth');
ParamsWindow.AddParam('ShowDepthFar',1,50);
ParamsWindow.AddParam('PassJitter',0.0001,0.01);
ParamsWindow.AddParam('FloorTileSize',0,100);
ParamsWindow.AddParam('RenderEnvironmentSkybox');



function GameRender(RenderTarget)
{
	RenderTarget.ClearColour(1,0,0);
	Window.RenderCounter.Add();
	
	if ( RenderGameFunc )
		RenderGameFunc( RenderTarget );
}

let RenderGameFunc = null;

const StartTime = Pop.GetTimeNowMs();


function RenderScene(RenderTarget,Camera,Runtime)
{
	const Quad = GetAsset('Quad',RenderTarget);
	const Shader = GetAsset(Runtime.SceneShader,RenderTarget);

	const EnviromentMapEquirect = Runtime.EnvironmentMapFile;
	const NoiseTexture = Runtime.NoiseTexture;

	const WorldToCameraMatrix = Camera.GetWorldToCameraMatrix();
	const CameraProjectionMatrix = Camera.GetProjectionMatrix(RenderTarget.GetScreenRect());
	const ScreenToCameraTransform = Math.MatrixInverse4x4(CameraProjectionMatrix);
	const CameraToWorldTransform = Math.MatrixInverse4x4(WorldToCameraMatrix);
	const LocalToWorldTransform = Camera.GetLocalToWorldFrustumTransformMatrix();
	//const LocalToWorldTransform = Math.CreateIdentityMatrix();
	const WorldToLocalTransform = Math.MatrixInverse4x4(LocalToWorldTransform);

	const SetUniforms = function (Shader)
	{
		function SetUniform(Key)
		{
			Shader.SetUniform(Key,Params[Key]);
		}
		Object.keys(Params).forEach(SetUniform);

		Shader.SetUniform('VertexRect',[0,0,1,1]);
		Shader.SetUniform('ScreenToCameraTransform',ScreenToCameraTransform);
		Shader.SetUniform('CameraToWorldTransform',CameraToWorldTransform);
		Shader.SetUniform('LocalToWorldTransform',LocalToWorldTransform);
		Shader.SetUniform('WorldToLocalTransform',WorldToLocalTransform);
		Shader.SetUniform('EnviromentMapEquirect',EnviromentMapEquirect);
		Shader.SetUniform('NoiseTexture',NoiseTexture);
		const Time = (Pop.GetTimeNowMs() - StartTime) / 1000;
		Shader.SetUniform('Time',Time);
	}
	RenderTarget.SetBlendModeAlpha();
	RenderTarget.DrawGeometry(Quad,Shader,SetUniforms);
}

function MeltGameRender(RenderTarget,GameState)
{
	const State = GameState.State;
	const Runtime = GameState.Runtime;
	RenderTarget.ClearColour(...Params.ClearColour);
	Runtime.Camera.FovVertical = Params.FovVertical;

	function RenderCamera(Camera,CameraIndex)
	{
		const RenderTexture = Camera.RenderTexture;
		if (RenderTexture)
		{
			function RenderEye(RenderTarget)
			{
				const Colours = [[1,0,0],[0,1,0],[0,0,1]];
				//RenderTarget.ClearColour(...Colours[CameraIndex]);
				RenderScene(RenderTarget,Camera,Runtime);
			}
			RenderTarget.RenderToRenderTarget(RenderTexture,RenderEye);
		}
		else
		{
			//	sometimes this doesnt render?
			RenderScene(RenderTarget,Camera,Runtime);
		}

		if (Camera.OnFinishedRender)
			Camera.OnFinishedRender();
	}
	Cameras.forEach(RenderCamera);
}

//	I think I've forgotten to commit a version of the engine, temp async call
if (!Pop.LoadFileAsStringAsync) Pop.LoadFileAsStringAsync = Pop.LoadFileAsString;
if (!Pop.LoadFileAsImageAsync) Pop.LoadFileAsImageAsync = Pop.LoadFileAsImage;

async function LoadAssets()
{
	const AssetFilenames =
	[
	 SceneRenderShaderFilename,
	 'Quad.vert.glsl'
	 ];

	//	for web... maybe this can go now?
	if ( Pop.AsyncCacheAssetAsString )
	{
		const CacheAssetPromises = AssetFilenames.map( Pop.AsyncCacheAssetAsString );
		await Promise.all(CacheAssetPromises);
	}
	
	const AssetPromises = AssetFilenames.map( Pop.LoadFileAsStringAsync );
	await Promise.all(AssetPromises);
	return true;
}

async function ResetGame()
{
	await LoadAssets();

	//	reset/spawn actors
	
	//	game state
	const Game = {};
	Game.State = {};
	
	Game.Runtime = {};
	Game.Runtime.Render = function(RenderTarget)	{	MeltGameRender(RenderTarget,Game);	}
	Game.Runtime.Camera = new Pop.Camera();
	Game.Runtime.Camera.Position = [0,0.5,3];
	Game.Runtime.SceneShader = RegisterShaderAssetFilename(SceneRenderShaderFilename,'Quad.vert.glsl');
	Game.Runtime.EnvironmentMapFile = await Pop.LoadFileAsImageAsync(EnvironmentMapFilename);
	Game.Runtime.NoiseTexture = await Pop.LoadFileAsImageAsync(NoiseFilename);

	Cameras.push(Game.Runtime.Camera);
	UserCamera = Game.Runtime.Camera;

	return Game;
}

async function WaitForUserStart()
{
	return true;
}

async function WaitForUserRestart()
{
	return true;
}


function GameIteration(GameState,Time,FrameDuration)
{
	//Pop.Debug(`Game Iteration ${Time}`);
}

async function GameLoop(GameState)
{
	const GameStartTime = Pop.GetTimeNowMs();
	function GetGameTimeSecs()
	{
		return (Pop.GetTimeNowMs() - GameStartTime) / 1000;
	}
	
	while( true )
	{
		const FrameDuration = 1/60;
		const GameTime = GetGameTimeSecs();
		//	todo: proper frame limiter
		await Pop.Yield(FrameDuration);
		
		GameIteration(GameState,GameTime,FrameDuration);
		
		//	is game finished?
		const IsGameFinished = GameTime > 30;
		if ( IsGameFinished )
			break;
	}
	
	const GameResult = {};
	GameResult.State = GameState;
	return GameResult;
}

async function AppLoop()
{
	while ( true )
	{
		const GameState = await ResetGame();
		RenderGameFunc = GameState.Runtime.Render;
		await WaitForUserStart();
		const GameResult = await GameLoop(GameState.State);
		ShowGameResult(GameResult);
		await WaitForUserRestart();
	}
}

AppLoop().then( Pop.ExitApp ).catch(Pop.Debug);



function OnNewPoses(Poses,CameraLeft,CameraRight)
{
	//Pop.Debug("Poses",JSON.stringify(Poses.Devices));
	function ValidDevice(Device)
	{
		return Device.IsConnected;
	}
	Poses.Devices = Poses.Devices.filter(ValidDevice);

	if (!Poses.Devices.length)
		return;

	function UpdateEye(Camera,Class)
	{
		function IsEyeClass(Device)
		{
			if (!Device.IsValidPose)
				return false;
			return Device.Class == Class;
		}

		const EyeDevice = Poses.Devices.find(IsEyeClass);
		if (!EyeDevice)
		{
			Pop.Debug(`Didnt find eye device ${Class}`);
			return;
		}
		
		Camera.GetWorldToCameraMatrix = function ()
		{
			const WorldToLocal = Math.MatrixInverse4x4(EyeDevice.LocalToWorld);
			//Pop.Debug("GetLocalToWorldMatrix",Hmd.LocalToWorld);
			return WorldToLocal;
		}
		Camera.ProjectionMatrix = EyeDevice.ProjectionMatrix;
	}

	UpdateEye(CameraLeft,"TrackedDeviceClass_HMD_LeftEye");
	UpdateEye(CameraRight,"TrackedDeviceClass_HMD_RightEye");

	//	update camera
	//Pop.Debug("Poses",JSON.stringify(Poses.Devices));
}

async function XrLoop()
{
	const Hmd = new Pop.Openvr.Hmd("Device Name");
	const PoseCounter = new Pop.FrameCounter("HMD poses");

	//	make textures for eyes
	const ImageWidth = 1512;
	const ImageHeight = 1680;
	const HmdLeft = new Pop.Image();
	const HmdRight = new Pop.Image();
	//	need to do this so when using as a render target, it has a size
	const InitPixels = new Uint8Array(ImageWidth * ImageHeight * 4);	
	HmdLeft.WritePixels(ImageWidth,ImageHeight,InitPixels,'RGBA');
	HmdRight.WritePixels(ImageWidth,ImageHeight,InitPixels,'RGBA');

	let HmdCameraLeft = new Pop.Camera();
	let HmdCameraRight = new Pop.Camera();
	HmdCameraLeft.RenderTexture = HmdLeft;
	HmdCameraRight.RenderTexture = HmdRight;
	HmdCameraLeft.Name = "Left";
	HmdCameraRight.Name = "Right";
	Cameras.push(HmdCameraLeft);
	Cameras.push(HmdCameraRight);

	HmdCameraRight.OnFinishedRender = function()
	{
		Hmd.SubmitFrame(HmdCameraLeft.RenderTexture,HmdCameraRight.RenderTexture);
	}

	while (true)
	{
		//	gr: current setup, this wont resolve until we've submitted a frame
		const PoseStates = await Hmd.WaitForPoses();
		//Pop.Debug("Got new poses" + JSON.stringify(PoseStates));
		PoseCounter.Add();

		OnNewPoses(PoseStates,HmdCameraLeft,HmdCameraRight);		
	}
}

//	try and run a vr/ar interface
XrLoop().then(Pop.Debug).catch(Pop.Debug);

