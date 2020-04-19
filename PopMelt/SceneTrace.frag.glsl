precision highp float;

in vec2 uv;
uniform mat4 ScreenToCameraTransform;
uniform mat4 CameraToWorldTransform;

uniform bool DrawStepHeat = false;
uniform float RefractionScalar = 0.66;

const float4 MoonSphere = float4(0,0,0,5);
uniform float MoonEdgeThickness = 0.2;
uniform float MoonEdgeThicknessNoiseFreq;
uniform float MoonEdgeThicknessNoiseScale;
uniform float BouncePastEdge;

uniform sampler2D EnviromentMapEquirect;
uniform sampler2D NoiseTexture;

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
	//float3 Rgb = texture2D( NoiseTexture, uv ).xyz;
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

float Range(float Min,float Max,float Value)
{
	return (Value-Min) / (Max-Min);
}

uniform float Time;

float GetMoonEdgeThickness(vec3 Position)
{
	float Thickness = MoonEdgeThickness;

	/*
	float2 uv;
	uv.x = Range( -MoonEdgeThicknessNoiseFreq, MoonEdgeThicknessNoiseFreq, Position.x );
	uv.y = Range( -MoonEdgeThicknessNoiseFreq, MoonEdgeThicknessNoiseFreq, Position.z * Position.y );
	float Offset = texture2D(NoiseTexture,uv).x;
*/
	//	gr: this is SO expensive
	//	"noise"
	float3 Offsetxyz = Position + float3(Time,Time,Time);
	//float Offset = sin(Offsetxy.x*MoonEdgeThicknessNoiseFreq) * cos(Offsetxy.y*MoonEdgeThicknessNoiseFreq);
	float OffsetX = sin(Offsetxyz.x*MoonEdgeThicknessNoiseFreq) * MoonEdgeThicknessNoiseScale;
	float OffsetY = cos(Offsetxyz.y*MoonEdgeThicknessNoiseFreq) * MoonEdgeThicknessNoiseScale;
	//float OffsetZ = sin(Offsetxyz.z*MoonEdgeThicknessNoiseFreq) * MoonEdgeThicknessNoiseScale;
	float OffsetZ = 1;//sin(Offsetxyz.z*MoonEdgeThicknessNoiseFreq) * MoonEdgeThicknessNoiseScale;
	//float Offset = OffsetX * OffsetY * OffsetZ;
	float Offset = abs(OffsetX);

	Thickness *= 1 + Offset;
	return Thickness;
}

float sdBox( vec3 p, vec3 b)
{
	vec3 q = abs(p) - b;
	return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}

float DistanceToMoonShape(float3 Position)
{
	bool UseBox = true;
	float Distance;
	float3 LocalPosition;
	
	if ( UseBox )
	{
		float3 BoxPos = MoonSphere.xyz;
		float3 BoxSize = float3(MoonSphere.w*0.5,MoonSphere.w*0.7,MoonSphere.w*0.8);
		LocalPosition = Position-BoxPos;
		Distance = sdBox( LocalPosition, BoxSize );
	}
	else
	{
		float MoonRadius = MoonSphere.w;
		LocalPosition = Position - MoonSphere.xyz;
		float3 DeltaToCenter = MoonSphere.xyz - Position;
		Distance = length( DeltaToCenter ) - MoonRadius;
	}
	Distance -= GetMoonEdgeThickness(LocalPosition);
	
	//	distance edge rather than solid
	Distance = abs(Distance);
	
	return Distance;
}



float3 sdBoxNormal(vec3 p,vec3 b)
{
	const float eps = 0.0001; // or some other value
	const vec2 h = vec2(eps,0);
	return normalize( vec3(sdBox(p+h.xyy,b) - sdBox(p-h.xyy,b),
						   sdBox(p+h.yxy,b) - sdBox(p-h.yxy,b),
						   sdBox(p+h.yyx,b) - sdBox(p-h.yyx,b) ) );
}

float DistanceToMoon(float3 Position,out float3 Normal)
{
	float Distance = DistanceToMoonShape(Position);
	//Normal = sdBoxNormal( LocalPosition, BoxSize );

	
	const float eps = 0.0001; // or some other value
	const vec2 h = vec2(eps,0);
	vec3 p = Position;
	//	gr: this doesn't seem right, I think we need to double check the xyz direction here
	//	like the test has to be in local space?
	Normal = normalize( vec3(DistanceToMoonShape(p+h.xyy) - DistanceToMoonShape(p-h.xyy),
							 DistanceToMoonShape(p+h.yxy) - DistanceToMoonShape(p-h.yxy),
							 DistanceToMoonShape(p+h.yyx) - DistanceToMoonShape(p-h.yyx) ) );

	//	invert normal when on the inside
	//float InsideDistance = DistanceToMoonShapeNoEdge(Position);
	//if ( InsideDistance < 0 )
	//	Normal = -Normal;
 
	return Distance;
}
/*


float DistanceToMoon(float3 Position,out float3 Normal)
{
	bool UseBox = true;
	float Distance;
	float3 LocalPosition;
	
	if ( UseBox )
	{
		float3 BoxPos = MoonSphere.xyz;
		float3 BoxSize = float3(MoonSphere.w*0.5,MoonSphere.w*0.7,MoonSphere.w*0.8);
		LocalPosition = Position-BoxPos;
		Distance = sdBox( LocalPosition, BoxSize );

		const float eps = 0.0001; // or some other value
		const vec2 h = vec2(eps,0);
		float3 p = LocalPosition;
		Normal = normalize( vec3(sdBox(p+h.xyy, BoxSize) - sdBox(p-h.xyy, BoxSize),
								 sdBox(p+h.yxy, BoxSize) - sdBox(p-h.yxy, BoxSize),
								 sdBox(p+h.yyx, BoxSize) - sdBox(p-h.yyx, BoxSize) ) );

	}
	else
	{
		float MoonRadius = MoonSphere.w;
		LocalPosition = Position - MoonSphere.xyz;
		float3 DeltaToCenter = MoonSphere.xyz - Position;
		Normal = -DeltaToCenter;
		Distance = length( DeltaToCenter ) - MoonRadius;
	}
	Distance -= GetMoonEdgeThickness(Position);
	
	if ( Distance < 0 )
		Normal = -Normal;

	//	distance edge rather than solid
	Distance = abs(Distance);
	
	return Distance;
}
*/

vec3 Slerp(vec3 p0, vec3 p1, float t)
{
	float dotp = dot(normalize(p0), normalize(p1));
	if ((dotp > 0.9999) || (dotp<-0.9999))
	{
		if (t<=0.5)
			return p0;
		return p1;
	}
	float theta = acos(dotp);
	vec3 P = ((p0*sin((1.0-t)*theta) + p1*sin(t*theta)) / sin(theta));
	return P;
}

bool refract(vec3 v,vec3 n,float ni_over_nt, out vec3 refracted)
{
	vec3 uv = normalize(v);
	float dt = dot(uv, n);
	float discriminant = 1.0 - ni_over_nt * ni_over_nt * (1.0 - dt * dt);
	if (discriminant > 0.0)
	{
		refracted = ni_over_nt * (uv - n * dt) - n * sqrt(discriminant);
		return true;
	} else {
		return false;
	}
}

/*
THit RayMarchPlane(TRay Ray,inout TDebug Debug)
{
 
}
*/

THit RayMarchSphere(TRay Ray,inout TDebug Debug)
{
	THit Hit;
	
	//	dont need to march here, but its fine for now
	const float MinDistance = 0.001;
	const float CloseEnough = MinDistance;
	const float MinStep = MinDistance;
	const float MaxDistance = 100.0;
	const int MaxSteps = 50;
	float3 StartPos = Ray.Pos;
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
			//	gr: we can make all this generic. Get a distance (including -X when inside)
			//		return a refrect option instead of bounce, then work this out to change the ray

			//float RefractionScalar = 0.66;	//	for chromatic abberation, use r=0.65 g=0.66 b=0.67
			vec3 Refracted = refract( normalize(Ray.Dir), normalize(Normal), RefractionScalar );
			vec3 Reflected = reflect( normalize(Ray.Dir), normalize(Normal) );
			float EdgeDot = (1.0-abs(dot(normalize(Ray.Dir),Normal)));
			Refracted = Slerp( Refracted, Reflected, EdgeDot );

			//Hit.Colour = NormalToRedGreen(EdgeDot);
			Hit.Colour = float3(1,1,1);
			Hit.Hit = true;

			//	gr; use EdgeDot > 0.5 for reflecting light?
			{
				Hit.HitPositionAndReflection.Dir = Refracted;
				Hit.HitPositionAndReflection.Pos = Position;
				
				//	step ever so slightly past the edge so bounce doesnt start on edge
				//	move this to generic code
				Hit.HitPositionAndReflection.Pos += Hit.HitPositionAndReflection.Dir * BouncePastEdge;
				//Hit.Colour = GetEnvironmentColour(Hit.HitPositionAndReflection.Dir);
				Hit.Bounce = true;
				//	test how far this ray has gone
				//Hit.Colour = NormalToRedGreen( length(StartPos-Position)/25 );
				//	difference in refraction
				//Hit.Colour = NormalToRedGreen( length(-Normal-Refracted));
			}
			
			//	inside
			if ( HitDistance < 0 )
			{
				Hit.Colour = float3(0,0,0);
				Hit.Bounce = false;
			}
			
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
#define BOUNCES	5
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

