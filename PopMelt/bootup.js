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
	const Camera = GetCamera ? GetCamera() : null;
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
	const Camera = GetCamera ? GetCamera() : null;
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
	const Camera = GetCamera ? GetCamera() : null;
	if ( Camera )
	{
		let Fly = Delta[1] * 50;
		//Fly *= Params.ScrollFlySpeed;
		Camera.OnCameraPanLocal( 0, 0, 0, true );
		Camera.OnCameraPanLocal( 0, 0, Fly, false );
	}
}

let GetCamera = null;



const Params = {};
Params.ClearColour = [0.8,0.5,0.1];
Params.FovVertical = 45;
Params.RefractionScalar = 0.66;
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

const ParamsWindow = new Pop.ParamsWindow(Params,function(){});
ParamsWindow.AddParam('RefractionScalar',0,1);
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



function GameRender(RenderTarget)
{
	RenderTarget.ClearColour(1,0,0);
	Window.RenderCounter.Add();
	
	if ( RenderGameFunc )
		RenderGameFunc( RenderTarget );
}

let RenderGameFunc = null;

const StartTime = Pop.GetTimeNowMs();

function MeltGameRender(RenderTarget,GameState)
{
	const State = GameState.State;
	const Runtime = GameState.Runtime;
	RenderTarget.ClearColour(...Params.ClearColour);
	
	Runtime.Camera.FovVertical = Params.FovVertical;
	GetCamera = function()	{	return Runtime.Camera;	}
	
	const Quad = GetAsset('Quad',RenderTarget);
	const Shader = GetAsset(Runtime.SceneShader,RenderTarget);
	const Camera = Runtime.Camera;
	
	const EnviromentMapEquirect = Runtime.EnvironmentMapFile;
	const NoiseTexture = Runtime.NoiseTexture;

	const WorldToCameraMatrix = Camera.GetWorldToCameraMatrix();
	const CameraProjectionMatrix = Camera.GetProjectionMatrix( RenderTarget.GetScreenRect() );
	const ScreenToCameraTransform = Math.MatrixInverse4x4( CameraProjectionMatrix );
	const CameraToWorldTransform = Math.MatrixInverse4x4( WorldToCameraMatrix );
	const LocalToWorldTransform = Camera.GetLocalToWorldFrustumTransformMatrix();
	//const LocalToWorldTransform = Math.CreateIdentityMatrix();
	const WorldToLocalTransform = Math.MatrixInverse4x4(LocalToWorldTransform);

	const SetUniforms = function(Shader)
	{
		function SetUniform(Key)
		{
			Shader.SetUniform( Key, Params[Key] );
		}
		Object.keys(Params).forEach(SetUniform);
		
		Shader.SetUniform('VertexRect',[0,0,1,1]);
		Shader.SetUniform('ScreenToCameraTransform',ScreenToCameraTransform);
		Shader.SetUniform('CameraToWorldTransform',CameraToWorldTransform);
		Shader.SetUniform('LocalToWorldTransform',LocalToWorldTransform);
		Shader.SetUniform('WorldToLocalTransform',WorldToLocalTransform);
		Shader.SetUniform('EnviromentMapEquirect',EnviromentMapEquirect);
		Shader.SetUniform('NoiseTexture',NoiseTexture);
		const Time = (Pop.GetTimeNowMs() - StartTime)/1000;
		Shader.SetUniform('Time',Time);
	}
	RenderTarget.SetBlendModeAlpha();
	RenderTarget.DrawGeometry( Quad, Shader, SetUniforms );
}

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
	Game.Runtime.SceneShader = RegisterShaderAssetFilename(SceneRenderShaderFilename,'Quad.vert.glsl');
	Game.Runtime.EnvironmentMapFile = await Pop.LoadFileAsImageAsync(EnvironmentMapFilename);
	Game.Runtime.NoiseTexture = await Pop.LoadFileAsImageAsync(NoiseFilename);
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
