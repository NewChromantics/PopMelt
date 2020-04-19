
Pop.Debug("Melttttttiiinnggg");


const Window = new Pop.Opengl.Window("Melt");
Window.OnRender = GameRender;
Window.OnMouseMove = function(){};


function GameRender(RenderTarget)
{
	RenderTarget.ClearColour(1,0,0);
	
	if ( RenderGameFunc )
		RenderGameFunc( RenderTarget );
}

let RenderGameFunc = null;

function MeltGameRender(RenderTarget,GameState)
{
	RenderTarget.ClearColour(0.8,0.5,0.1);
}

async function LoadAssets()
{
	const AssetFilenames = [];
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
	Game.Render = function(RenderTarget)	{	MeltGameRender(RenderTarget,Game);	}
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
	Pop.Debug(`Game Iteration ${Time}`);
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
		RenderGameFunc = GameState.Render;
		await WaitForUserStart();
		const GameResult = await GameLoop(GameState);
		ShowGameResult(GameResult);
		await WaitForUserRestart();
	}
}

AppLoop().then( Pop.ExitApp ).catch(Pop.Debug);
