precision highp float;

in vec2 uv;
uniform mat4 ScreenToCameraTransform;
uniform mat4 CameraToWorldTransform;
uniform bool DrawStepHeat;
uniform bool ShowDepth;
uniform float ShowDepthFar;
uniform float PassJitter;

//	materials
uniform float RefractionScalar;// = 0.66;
uniform float Time;
uniform float TimeMult;
uniform sampler2D EnviromentMapEquirect;
uniform sampler2D NoiseTexture;
uniform float FloorTileSize;
uniform bool RenderEnvironmentSkybox;

//	shapes
const float4 MoonSphere = float4(0,0,0,5);
uniform float MoonEdgeThickness;
uniform float MoonEdgeThicknessNoiseFreq;
uniform float MoonEdgeThicknessNoiseScale;
uniform float PlaneY;


//	algo tweaks
uniform float BouncePastEdge;
uniform float NormalViaRayStart;



struct TRay
{
	vec3 Pos;
	vec3 Dir;
};

struct TDebug
{
	int StepCount;
	int EnvMapSamples;
};
TDebug TDebug_Alloc()
{
	TDebug Debug;
	Debug.StepCount = 0;
	Debug.EnvMapSamples = 0;
	return Debug;
}

#define HIT_RESULT_MISS		0
#define HIT_RESULT_ABSORB	1
#define HIT_RESULT_REFRACT	2
#define HIT_RESULT_REFLECT	3

struct THit
{
	TRay	Ray;	//	pos of ray is intersection pos
	float3	SurfaceNormal;
	int		HitResult;
	float	Distance;
	//	todo: how much light/colour was absorbed in this hit
	float3	Colour;
};
bool Hit_IsMiss(THit Hit)
{
	return Hit.HitResult == HIT_RESULT_MISS;
}
bool Hit_IsHit(THit Hit)
{
	return !Hit_IsMiss(Hit);
}

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


float3 GetEnvironmentColour(float3 View,inout TDebug Debug)
{
	float2 uv = ViewToEquirect(View);
	
	float3 Rgb = float3(1.0,1.0,1.0);
	if (RenderEnvironmentSkybox)
	{
		//	this texture sample kills, but we only ever do it once! texture must be inefficient
		Rgb = texture2D(EnviromentMapEquirect, uv).xyz;
	}

	//	procedural ish
	float3 ViewRgb = (View + float3(1,1,1) ) * 0.5;	//	[-1.1] -> [0..1]
	Rgb = mix( Rgb, ViewRgb, 0.5 );
	
	//	debug samples
	//Rgb = (Debug.EnvMapSamples > 0) ? float3(1,0,0) : float3(0,1,0);
	
	//float3 Rgb = float3(1,0,0);
	//float3 Rgb = texture2D( NoiseTexture, uv ).xyz;
	Debug.EnvMapSamples++;
	return Rgb;
}

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
	Position += Time*TimeMult;
	
	//float Offset = sin(Offsetxy.x*MoonEdgeThicknessNoiseFreq) * cos(Offsetxy.y*MoonEdgeThicknessNoiseFreq);
	float OffsetX = sin(Position.x*MoonEdgeThicknessNoiseFreq);
	float OffsetY = cos(Position.y*MoonEdgeThicknessNoiseFreq);
	float OffsetZ = 1.0;//cos(Position.z*MoonEdgeThicknessNoiseFreq);
	float Offset = OffsetX * OffsetY * OffsetZ;
	
	//float Offset = sin( Position.x*MoonEdgeThicknessNoiseFreq);// * cos(Position.y*MoonEdgeThicknessNoiseFreq);
	
	Thickness *= 1.0 + (Offset * MoonEdgeThicknessNoiseScale);
	return Thickness;
}

float sdBox( vec3 p, vec3 b)
{
	vec3 q = abs(p) - b;
	return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}

float opSmoothUnion( float d1, float d2, float k )
{
	float h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
	return mix( d2, d1, h ) - k*h*(1.0-h);
	
}

float DistanceToMoonShape(float3 Position)
{
	bool UseBox = true;
	float Distance;
	float3 LocalPosition;
	
	if ( UseBox )
	{
		float3 BoxPos = MoonSphere.xyz;
		float3 BoxSize = float3(MoonSphere.w*0.5,MoonSphere.w*0.8,MoonSphere.w*1.5);
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
	
	bool AndSphere = true;
	if ( AndSphere )
	{
		float MoonRadius = MoonSphere.w;
		LocalPosition = Position - MoonSphere.xyz;
		float3 DeltaToCenter = MoonSphere.xyz - Position;
		float SphereDistance = length( DeltaToCenter ) - MoonRadius;
		//Distance = min(SphereDistance,Distance);
		Distance = opSmoothUnion( SphereDistance, Distance, 1.01 );
	}
	
	Distance -= GetMoonEdgeThickness(LocalPosition);
	
	//	distance edge rather than solid
	Distance = abs(Distance);
	
	return Distance;
}



float3 sdBoxNormal(vec3 p,vec3 b)
{
	const float eps = 0.0001; // or some other value
	const vec2 h = vec2(eps,0.0);
	return normalize( vec3(sdBox(p+h.xyy,b) - sdBox(p-h.xyy,b),
						   sdBox(p+h.yxy,b) - sdBox(p-h.yxy,b),
						   sdBox(p+h.yyx,b) - sdBox(p-h.yyx,b) ) );
}

float3 DistanceToMoonNormal(float3 Position)
{
	//	gr: newer method, very little difference to other one, but this is a fewer number of calls
	//	https://www.shadertoy.com/view/Xds3zN
	vec2 e = vec2(1.0,-1.0)*0.5773*0.0005;
	float3 Normal = normalize( e.xyy*DistanceToMoonShape( Position + e.xyy ) +
					 e.yyx*DistanceToMoonShape( Position + e.yyx ) +
					 e.yxy*DistanceToMoonShape( Position + e.yxy ) +
					 e.xxx*DistanceToMoonShape( Position + e.xxx ) );
	return Normal;
	
	/*
	// inspired by tdhooper and klems - a way to prevent the compiler from inlining map() 4 times
#define ZERO (min(1,0))
	vec3 n = vec3(0.0);
	for( int i=ZERO; i<4; i++ )
	{
		vec3 e = 0.5773*(2.0*vec3((((i+3)>>1)&1),((i>>1)&1),(i&1))-1.0);
		n += e*DistanceToMoonShape(Position+0.0005*e);
	}
	return normalize(n);
	 */
}


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

//	some platforms have refract()
#define refract2	refract

#if !defined(refract2)
vec3 refract2(vec3 v,vec3 n,float ni_over_nt)
{
	vec3 uv = normalize(v);
	float dt = dot(uv, n);
	float discriminant = 1.0 - ni_over_nt * ni_over_nt * (1.0 - dt * dt);
	if (discriminant > 0.0)
	{
		float3 refracted = ni_over_nt * (uv - n * dt) - n * sqrt(discriminant);
		return refracted;
	}
	else
	{
		return n;
	}
}
#endif


TRay Hit_GetRefraction(THit Hit)
{
	//	gr: we can make all this generic. Get a distance (including -X when inside)
	//		return a refrect option instead of bounce, then work this out to change the ray
	//	gr: todo: do inside-distance stuff
	
	//float RefractionScalar = 0.66;	//	for chromatic abberation, use r=0.65 g=0.66 b=0.67
	vec3 Refracted = refract2( normalize(Hit.Ray.Dir), normalize(Hit.SurfaceNormal), RefractionScalar );
	vec3 Reflected = reflect( normalize(Hit.Ray.Dir), normalize(Hit.SurfaceNormal) );
	float EdgeDot = (1.0-abs(dot(normalize(Hit.Ray.Dir),Hit.SurfaceNormal)));
	Refracted = Slerp( Refracted, Reflected, EdgeDot );
	
	TRay Reflection;
	Reflection.Pos = Hit.Ray.Pos;
	Reflection.Dir = Refracted;
	
	//	step ever so slightly past the edge so bounce doesnt start on edge
	//	gr: move to scene bouncer?
	Reflection.Pos += Reflection.Dir * BouncePastEdge;
	return Reflection;
}


THit RayMarchPlane(TRay Ray,inout TDebug Debug)
{
	//Ray.Pos.y += 30;
	float3 PlaneNormal = float3(0,1,0);
	float PlaneOffset = PlaneY;
	
	//	https://gist.github.com/doxas/e9a3d006c7d19d2a0047
	float PlaneDistance = -PlaneOffset;
	float Denom = dot( Ray.Dir, PlaneNormal);
	float t = -(dot( Ray.Pos, PlaneNormal) + PlaneDistance) / Denom;
	/*
	//	wrong side, enable for 2 sided
	if ( t <= 0 )
	{
		THit Hit;
		Hit.Hit = false;
		return Hit;
	}
	*/
	float t_min = 0.001;
	float t_max = 99999.0;
	if (t < t_min || t > t_max)
	{
		THit Hit;
		Hit.HitResult = HIT_RESULT_MISS;
		return Hit;
	}
	
	
	
	THit Hit;
	Hit.HitResult = HIT_RESULT_ABSORB;
	Hit.Distance = t;
	Hit.Ray = Ray;
	Hit.Ray.Pos += Ray.Dir * t;
	Hit.Ray.Dir = Ray.Dir;
	Hit.SurfaceNormal = PlaneNormal;
	Hit.Colour = float3(0,0,0);

	//	put holes in the floor
	float SquareSize = FloorTileSize;
	float2 xz = fract(Hit.Ray.Pos.xz / (SquareSize*2.0));
	bool Oddx = xz.x<0.5;
	bool Oddy = xz.y<0.5;
	if ( Oddx == Oddy )
		Hit.HitResult = HIT_RESULT_REFLECT;
	
	return Hit;
}


THit RayMarchSphere(TRay Ray,inout TDebug Debug)
{
	THit Hit;
	Hit.HitResult = HIT_RESULT_MISS;
	
	//	dont need to march here, but its fine for now
	const float MinDistance = 0.001;
	const float CloseEnough = MinDistance;
	const float MinStep = MinDistance;
	//const float MaxDistance = 100.0;
#define MaxSteps 40
	//const int MaxSteps = 10;
	float3 StartPos = Ray.Pos;
	float RayTime = 0.01;
	
	for ( int s=0;	s<MaxSteps;	s++ )
	{
		Debug.StepCount++;
		vec3 Position = Ray.Pos + Ray.Dir * RayTime;
		float MoonDistance = DistanceToMoonShape( Position );
		float HitDistance = MoonDistance;
		
		//RayTime += max( HitDistance, MinStep );
		RayTime += HitDistance;
		if ( HitDistance < CloseEnough )
		{
			//	special call to get normal
			//	gr: if we calc the normal too close to the surface, we get (I think) some nan/0 normals. Too far away and its not fine enough!
			//	just need a tiny tiny offset!
			//float3 Normal = DistanceToMoonNormal( mix(Position,Ray.Pos,NormalViaRayStart) );
			Hit.SurfaceNormal = DistanceToMoonNormal( Position-Ray.Dir*NormalViaRayStart );
			Hit.Ray.Pos = Position;
			Hit.Ray.Dir = Ray.Dir;
			
			Hit.Colour = float3(1,1,1);
			Hit.HitResult = HIT_RESULT_REFRACT;
			//Hit.HitResult = HIT_RESULT_REFLECT;
			Hit.Distance = length(Position - Ray.Pos);

			//	inside
			if ( HitDistance < 0.0 )
			{
				Hit.Colour = float3(0,0,0);
				Hit.HitResult = HIT_RESULT_ABSORB;
			}
			
			return Hit;
		}
	}
	
	return Hit;
}

THit AllocHit(TRay StartRay)
{
	THit NewHit;
	NewHit.Ray = StartRay;
	NewHit.HitResult = HIT_RESULT_MISS;
	return NewHit;
}

//	returns intersction pos, w=success
THit RayMarchScene(TRay Ray,inout TDebug Debug)
{
	//	pick best hit
	THit Hit1 = RayMarchPlane( Ray, Debug );
	THit Hit0 = RayMarchSphere( Ray, Debug );
	//Hit0.HitResult = HIT_RESULT_MISS;
	Hit0.Distance = Hit_IsHit(Hit0) ? Hit0.Distance : 999999.0;
	Hit1.Distance = Hit_IsHit(Hit1) ? Hit1.Distance : 999999.0;

	//	no tenary on web
	//return ( Hit0.Distance < Hit1.Distance ) ? Hit0 : Hit1;
	if ( Hit0.Distance < Hit1.Distance )
		return Hit0;
	else
		return Hit1;
}

THit GetSkyboxHit(TRay Ray,out TDebug Debug)
{
	THit Hit;
	Hit.Ray = Ray;
	Hit.SurfaceNormal = Ray.Dir;
	Hit.HitResult = HIT_RESULT_ABSORB;
	Hit.Colour = GetEnvironmentColour( Ray.Dir, Debug );
	return Hit;
}

//	returns intersction pos, w=success
THit RayTraceScene(TRay Ray,out TDebug Debug)
{
#define BOUNCES	5
	//	save last hit in case we exceed bounces
	THit LastHit;
	//	should also be saving details about the first hit, as thats the actual surface
	//THit FirstHit;
	float FirstHitDistance = 999.0;
	
	for (int Bounce=0;	Bounce<BOUNCES;	Bounce++)
	{
		THit NewHit = RayMarchScene( Ray, Debug );
		
		if ( Bounce == 0 )
			FirstHitDistance = NewHit.Distance;

		if ( Hit_IsMiss(NewHit) )
		{
			//	didn't hit on first bounce = miss
			if ( Bounce == 0 )
				return NewHit;
		
			//	this was a bounce, hit the sky box
			NewHit = GetSkyboxHit(Ray,Debug);
			//	restore original hit depth
			NewHit.Distance = FirstHitDistance;
			return NewHit;
		}
		else if ( NewHit.HitResult == HIT_RESULT_REFLECT )
		{
			//	save in case it's the last bounce
			LastHit = NewHit;

			//	reflect - todo may need to step away from surface like in refraction
			Ray.Pos = NewHit.Ray.Pos;
			Ray.Dir = reflect( normalize(NewHit.Ray.Dir), normalize(NewHit.SurfaceNormal) );
			//Ray.Dir = NewHit.SurfaceNormal;
			continue;
		}
		else if ( NewHit.HitResult == HIT_RESULT_REFRACT )
		{
			//	save in case it's the last bounce
			LastHit = NewHit;
			
			//	reflect
			Ray = Hit_GetRefraction(NewHit);
			continue;
		}
		else
		{
			//	abosrb
			//	hit surface, ray stops here
			//	gr: break & LastHit isn't returning properly
			NewHit.Distance = FirstHitDistance;
			return NewHit;
			LastHit = NewHit;
			break;
		}
	}
	LastHit.Distance = FirstHitDistance;
	return LastHit;
}


void main()
{
	TRay Ray = GetWorldRay();
	TDebug Debug = TDebug_Alloc();
	float4 EnvColour = float4( GetEnvironmentColour(Ray.Dir,Debug), 1.0 );
	
	THit SceneHit = RayTraceScene( Ray, Debug );
	float4 SceneColour = float4( SceneHit.Colour, Hit_IsHit(SceneHit) ? 1.0 : 0.0 );
	
	//	first colour should always be solid so either bg or hit
	SceneColour = mix( EnvColour, SceneColour, SceneColour.w );

	//	gr: rubbish AND slow
	/*
#define PASSES	0
	float2 Jitter[4];//PASSES];
	Jitter[0] = float2( PassJitter*-0.5, PassJitter*-0.5 );
	Jitter[1] = float2( PassJitter*0.5, PassJitter*-0.5 );
	Jitter[2] = float2( PassJitter*0.5, PassJitter*0.5 );
	Jitter[3] = float2( PassJitter*-0.5, PassJitter*0.5 );
	
#if PASSES > 0	//	eek without this, we lose 10fps
	for ( int p=0;	p<PASSES;	p++ )
	{
		//	jitter ray
		TRay PRay = Ray;
		PRay.Dir.xy += Jitter[p];
		THit SceneHit2 = RayTraceScene( PRay, Debug );
		float Hitw = Hit_IsHit(SceneHit) ? 1.0 : 0.0;
		SceneColour.xyz = mix( SceneColour.xyz, SceneHit2.Colour, Hitw*0.5 );
	}
#endif
	*/
	gl_FragColor = SceneColour;
	
	if ( ShowDepth && Hit_IsHit(SceneHit) )
	{
		float DistanceNorm = SceneHit.Distance/ShowDepthFar;
		gl_FragColor = float4( DistanceNorm,DistanceNorm,DistanceNorm,1.0);
	}
}

