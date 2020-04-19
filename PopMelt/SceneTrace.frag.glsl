precision highp float;

in vec2 uv;
uniform mat4 ScreenToCameraTransform;
uniform mat4 CameraToWorldTransform;

uniform bool DrawStepHeat = false;

const float4 MoonSphere = float4(0,0,0,3);

uniform sampler2D EnviromentMapEquirect;

struct TRay
{
	vec3 Pos;
	vec3 Dir;
};

struct TDebug
{
	int StepCount;
};

struct THit
{
	TRay HitPositionAndReflection;
	bool Hit;
	
	//	todo: how much light/colour was absorbed in this hit
	bool Bounce;
	float3 Colour;
};

vec3 ScreenToWorld(float2 uv,float z)
{
	float x = mix( -1.0, 1.0, uv.x );
	float y = mix( 1.0, -1.0, uv.y );
	vec4 ScreenPos4 = vec4( x, y, z, 1 );
	vec4 CameraPos4 = ScreenToCameraTransform * ScreenPos4;
	vec4 WorldPos4 = CameraToWorldTransform * CameraPos4;
	vec3 WorldPos = WorldPos4.xyz / WorldPos4.w;
	return WorldPos;
}

TRay GetWorldRay()
{
	float Near = 0.01;
	float Far = 1000.0;
	TRay Ray;
	Ray.Pos = ScreenToWorld( uv, Near );
	Ray.Dir = ScreenToWorld( uv, Far ) - Ray.Pos;
	
	//	gr: this is backwards!
	Ray.Dir = -normalize( Ray.Dir );
	return Ray;
}

vec3 GetRayPositionAtTime(TRay Ray,float Time)
{
	return Ray.Pos + ( Ray.Dir * Time );
}


#define PI 3.14159265359

float atan2(float x,float y)
{
	return atan( y, x );
}


//	https://github.com/SoylentGraham/PopUnityCommon/blob/master/PopCommon.cginc#L298
float2 ViewToEquirect(float3 View3)
{
	View3 = normalize(View3);
	float2 longlat = float2(atan2(View3.x, View3.z) + PI, acos(-View3.y));
	
	//longlat.x += lerp( 0, UNITY_PI*2, Range( 0, 360, LatitudeOffset ) );
	//longlat.y += lerp( 0, UNITY_PI*2, Range( 0, 360, LongitudeOffset ) );
	
	float2 uv = longlat / float2(2.0 * PI, PI);
	
	return uv;
}

float3 GetEnvironmentColour(float3 View)
{
	float2 uv = ViewToEquirect(View);
	float3 Rgb = texture2D( EnviromentMapEquirect, uv ).xyz;
	return Rgb;
}

float3 NormalToRedGreen(float Normal)
{
	if ( Normal < 0.5 )
	{
		Normal /= 0.5;
		return float3( 1.0, Normal, 0.0 );
	}
	else
	{
		Normal -= 0.5;
		Normal /= 0.5;
		return float3( 1.0-Normal, 1.0, 0.0 );
	}
}


float DistanceToMoon(float3 Position,out float3 Normal)
{
	float3 DeltaToSurface = MoonSphere.xyz - Position;
	Normal = -normalize( DeltaToSurface );
	float MoonRadius = MoonSphere.w;
	float3 MoonSurfacePoint = MoonSphere.xyz + Normal * MoonRadius;
	float Distance = length( Position - MoonSurfacePoint );
	return Distance;
}

THit RayMarchSphere(TRay Ray,inout TDebug Debug)
{
	THit Hit;
	
	//	dont need to march here, but its fine for now
	const float MinDistance = 0.001;
	const float CloseEnough = MinDistance;
	const float MinStep = MinDistance;
	const float MaxDistance = 100.0;
	const int MaxSteps = 50;
	
	float RayTime = 0.01;
	for ( int s=0;	s<MaxSteps;	s++,Debug.StepCount++ )
	{
		vec3 Position = Ray.Pos + Ray.Dir * RayTime;
		float3 Normal;
		float MoonDistance = DistanceToMoon( Position, Normal );
		float HitDistance = MoonDistance;
		
		//RayTime += max( HitDistance, MinStep );
		RayTime += HitDistance;
		if ( HitDistance < CloseEnough )
		{
			Hit.HitPositionAndReflection.Pos = Position + Normal;
			Hit.HitPositionAndReflection.Dir = Normal;
			Hit.Colour = NormalToRedGreen( float(s)/float(MaxSteps) );
			Hit.Colour = Normal;
			Hit.Bounce = true;	//	shiny!
			Hit.Hit = true;
			return Hit;
		}
		
		if (RayTime > MaxDistance)
			break;//return float4(Position,0);
	}
	
	Hit.Hit = false;
	return Hit;
}

THit AllocHit(TRay StartRay)
{
	THit NewHit;
	NewHit.HitPositionAndReflection = StartRay;
	NewHit.Hit = false;
	NewHit.Bounce = false;
	return NewHit;
}

//	returns intersction pos, w=success
THit RayMarchScene(TRay Ray,inout TDebug Debug)
{
	//	pick best hit
	THit Hit0 = RayMarchSphere( Ray, Debug );
	return Hit0;
}

THit GetSkyboxHit(TRay Ray,out TDebug Debug)
{
	THit Hit;
	Hit.Hit = true;
	Hit.Bounce = false;
	Hit.Colour = GetEnvironmentColour( Ray.Dir );
	return Hit;
}

//	returns intersction pos, w=success
THit RayTraceScene(TRay Ray,out TDebug Debug)
{
#define BOUNCES	4
	//	save last hit in case we exceed bounces
	THit LastHit;
	for (int Bounce=0;	Bounce<BOUNCES;	Bounce++)
	{
		THit NewHit = RayMarchScene( Ray, Debug );

		if ( !NewHit.Hit )
		{
			//	didn't hit on first bounce = miss
			if ( Bounce == 0 )
				return NewHit;
		
			//	this was a bounce, hit the sky box
			return GetSkyboxHit(Ray,Debug);
		}
		
		if ( NewHit.Bounce )
		{
			//	save in case it's the last bounce
			LastHit = NewHit;

			//	reflect
			Ray = NewHit.HitPositionAndReflection;
			continue;
		}
	
		//	hit surface, ray stops here
		//	gr: break & LastHit isn't returning properly
		return NewHit;
		LastHit = NewHit;
		break;
	}
	return LastHit;
}


void main()
{
	TRay Ray = GetWorldRay();
	float4 Colour = float4( GetEnvironmentColour(Ray.Dir), 1 );
	
	TDebug Debug;
	THit SceneHit = RayTraceScene( Ray, Debug );
	/*
	if ( SceneHit.Hit )
		gl_FragColor = float4(0,1,0,1);
	else
		gl_FragColor = float4(1,0,0,1);
	return;
*/
	float4 SceneColour = float4( SceneHit.Colour, SceneHit.Hit ? 1.0 : 0.0 );
	/*
	float StepHeat =
	float4 SphereColour = RayMarchSphere( Ray, StepHeat );
	if ( DrawStepHeat )
		SphereColour.xyz = NormalToRedGreen( 1.0 - StepHeat );
	*/
	Colour = mix( Colour, SceneColour, SceneColour.w );
	gl_FragColor = Colour;
}

