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


void GetMoonHeight(float3 MoonNormal,out float Height)
{
	Height = 0;
}



void GetMoonColourHeight(float3 MoonNormal,out float3 Colour,out float Height)
{
	Colour = float3(1,1,1);
	Height = 0;
}




float DistanceToMoon(float3 Position)
{
	float3 DeltaToSurface = MoonSphere.xyz - Position;
	float3 Normal = -normalize( DeltaToSurface );
	float MoonRadius = MoonSphere.w;
	float3 MoonSurfacePoint = MoonSphere.xyz + Normal * MoonRadius;
	float Distance = length( Position - MoonSurfacePoint );
	return Distance;
}

float3 GetMoonColour(float3 Position)
{
	return float3(1,1,1);
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



//	returns intersction pos, w=success
float4 RayMarchSpherePos(TRay Ray,out float StepHeat)
{
	const float MinDistance = 0.001;
	const float CloseEnough = MinDistance;
	const float MinStep = MinDistance;
	const float MaxDistance = 100.0;
	const int MaxSteps = 50;
	
	float RayTime = 0.01;
	
	for ( int s=0;	s<MaxSteps;	s++ )
	{
		StepHeat = float(s)/float(MaxSteps);
		vec3 Position = Ray.Pos + Ray.Dir * RayTime;
		float MoonDistance = DistanceToMoon( Position );
		float HitDistance = MoonDistance;
		
		//RayTime += max( HitDistance, MinStep );
		RayTime += HitDistance;
		if ( HitDistance < CloseEnough )
			return float4(Position,1);
		
		if (RayTime > MaxDistance)
			return float4(Position,0);
	}
	StepHeat = 1.0;
	return float4(0,0,0,-1);
}


float4 RayMarchSphere(TRay Ray,out float StepHeat)
{
	float4 Intersection = RayMarchSpherePos( Ray, StepHeat );
	//if ( Intersection.w < 0.0 )
	//	return float4(1,0,0,0);
	
	float3 Colour = GetMoonColour( Intersection.xyz );
	return float4( Colour, Intersection.w );
}

void main()
{
	TRay Ray = GetWorldRay();
	float4 Colour = float4( GetEnvironmentColour(Ray.Dir), 1 );
	
	float StepHeat;
	float4 SphereColour = RayMarchSphere( Ray, StepHeat );
	if ( DrawStepHeat )
		SphereColour.xyz = NormalToRedGreen( 1.0 - StepHeat );
	
	Colour = mix( Colour, SphereColour, SphereColour.w );
	gl_FragColor = Colour;
}

