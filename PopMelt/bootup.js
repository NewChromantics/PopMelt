Pop.Debug("Melttttttiiinnggg");

Pop.Include = function(Filename)
{
	const Source = Pop.LoadFileAsString(Filename);
	return Pop.CompileAndRun( Source, Filename );
}

Pop.Include('PopEngineCommon/PopShaderCache.js');
Pop.Include('PopEngineCommon/PopFrameCounter.js');
Pop.Include('PopEngineCommon/PopMath.js');
Pop.Include('PopEngineCommon/ParamsWindow.js');
Pop.Include('PopEngineCommon/PopCamera.js');

Pop.Include('AssetManager.js');



const Window = new Pop.Opengl.Window("Melt");
Window.OnRender = GameRender;
Window.OnMouseMove = function(){};

const Params = {};
Params.ClearColour = [0.8,0.5,0.1];
Params.FovVertical = 45;

function GameRender(RenderTarget)
{
	RenderTarget.ClearColour(1,0,0);
	
	if ( RenderGameFunc )
		RenderGameFunc( RenderTarget );
}

let RenderGameFunc = null;

function MeltGameRender(RenderTarget,GameState)
{
	const State = GameState.State;
	const Runtime = GameState.Runtime;
	RenderTarget.ClearColour(...Params.ClearColour);
	
	Runtime.Camera.FovVertical = Params.FovVertical;
	
	const Quad = GetAsset('Quad',RenderTarget);
	const Shader = GetAsset(Runtime.SceneShader,RenderTarget);
	const Camera = Runtime.Camera;
	
	const EnviromentMapEquirect = Runtime.EnvironmentMapFile;
	
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
	}
	RenderTarget.SetBlendModeAlpha();
	RenderTarget.DrawGeometry( Quad, Shader, SetUniforms );
}

async function LoadAssets()
{
	const AssetFilenames =
	[
	 'SceneMarch.frag.glsl',
	 'SceneTrace.frag.glsl',
	 'Quad.vert.glsl'
	];
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
	Game.Runtime.SceneShader = RegisterShaderAssetFilename('SceneTrace.frag.glsl','Quad.vert.glsl');
	Game.Runtime.EnvironmentMapFile = await Pop.LoadFileAsImageAsync('TestEnvMapEquirect.jpg');
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
