#version 300 es
precision highp float;

uniform sampler2D u_Pos;
uniform sampler2D u_Nor;
uniform sampler2D u_Albedo;
uniform sampler2D u_SceneInfo; // extend to multiple textures
uniform int u_SceneTexWidth; // extend to multiple size
uniform int u_SceneTexHeight; // extend to multiple size
uniform int u_TriangleCount;

// currently one light
uniform vec4 u_LightPos;
uniform float u_Time;

uniform vec3 u_Camera;
uniform float u_Width;
uniform float u_Height;
uniform mat4 u_ViewInv;
uniform mat4 u_ProjInv;
uniform float u_Far;


in vec2 fs_UV;
out vec4 out_Col;

const int MAX_DEPTH = 2;
const float EPSILON = 0.0001;
const float FLT_MAX = 1000000.0;

vec3 missColor = vec3(0.0, 0.0, 0.0);


// light source should be mesh  OK
// lauch ray from gbuffer: what if miss at first place OK
// intersection with triangles: closest  OK
// light source need to be hard coded in shader
// in out problem
// reflection ray intersects with non-reflective triangle??
// hit no triangle/hit no light: set to missColor or not???
// when shoot rays from gbuffer, need to set hitLight to true for light mesh
// three conditions: hit light, hit outside, hit triangles but not light

struct Ray{
    vec3 origin;
    vec3 direction;
    vec3 color;
    int remainingBounces;
    bool hitLight;
};

float noise2d(float x, float y) {
    return fract(sin(dot(vec2(x, y), vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 calculateRandomDirectionInHemisphere(vec3 normal) {
    // coorelation is still high
    float x = noise2d(fs_UV.x, fs_UV.y) * 2.0 - 1.0;
    float y = noise2d(x, x) * 2.0 - 1.0;
    float z = noise2d(x, y) * 2.0 - 1.0;
    vec3 randomV = normalize(vec3(x, y, z));
    if (dot(randomV, normal) < 0.0) {
        randomV *= -1.0;
    }
    return randomV;
}

void getTrianglePosition(in int index, out vec3 p0, out vec3 p1, out vec3 p2) {
    int row = index / u_SceneTexWidth;
    int col = index - row * u_SceneTexWidth;

    row = row * 11;

    float u = (float(col) + 0.5) / float(u_SceneTexWidth);
    float v0 = (float(row) + 0.5) / float(u_SceneTexHeight);
    float v1 = (float(row) + 1.5) / float(u_SceneTexHeight);
    float v2 = (float(row) + 2.5) / float(u_SceneTexHeight);

    p0 = texture(u_SceneInfo, vec2(u, v0)).xyz;
    p1 = texture(u_SceneInfo, vec2(u, v1)).xyz;
    p2 = texture(u_SceneInfo, vec2(u, v2)).xyz;
}

vec3 getTriangleNormal(in int index) {
    int row = index / u_SceneTexWidth;
    int col = index - row * u_SceneTexWidth;

    row = row * 11;

    float u = (float(col) + 0.5) / float(u_SceneTexWidth);
    float v0 = (float(row) + 3.5) / float(u_SceneTexHeight);
    float v1 = (float(row) + 4.5) / float(u_SceneTexHeight);
    float v2 = (float(row) + 5.5) / float(u_SceneTexHeight);

    vec3 n0 = normalize(texture(u_SceneInfo, vec2(u, v0)).xyz);
    vec3 n1 = normalize(texture(u_SceneInfo, vec2(u, v1)).xyz);
    vec3 n2 = normalize(texture(u_SceneInfo, vec2(u, v2)).xyz);

    return (n0 + n1 + n2) / 3.0;
}

void getTriangleUV(in int index, out vec2 UV0, out vec2 UV1, out vec2 UV2) {
    int row = index / u_SceneTexWidth;
    int col = index - row * u_SceneTexWidth;

    row = row * 11;

    float u = (float(col) + 0.5) / float(u_SceneTexWidth);
    float v0 = (float(row) + 6.5) / float(u_SceneTexHeight);
    float v1 = (float(row) + 7.5) / float(u_SceneTexHeight);
    float v2 = (float(row) + 8.5) / float(u_SceneTexHeight);

    UV0 = texture(u_SceneInfo, vec2(u, v0)).xy;
    UV1 = texture(u_SceneInfo, vec2(u, v1)).xy;
    UV2 = texture(u_SceneInfo, vec2(u, v2)).xy;
}

vec4 getTriangleBaseColor(in int index) {
    int row = index / u_SceneTexWidth;
    int col = index - row * u_SceneTexWidth;

    row = row * 11;

    float u = (float(col) + 0.5) / float(u_SceneTexWidth);
    float v0 = (float(row) + 9.5) / float(u_SceneTexHeight);

    return  texture(u_SceneInfo, vec2(u, v0));
}

vec4 getTriangleMaterial(in int index) {
    int row = index / u_SceneTexWidth;
    int col = index - row * u_SceneTexWidth;

    row = row * 11;

    float u = (float(col) + 0.5) / float(u_SceneTexWidth);
    float v0 = (float(row) + 10.5) / float(u_SceneTexHeight);
    
    return texture(u_SceneInfo, vec2(u, v0));
}


// reference to 
// https://en.wikipedia.org/wiki/M%C3%B6ller%E2%80%93Trumbore_intersection_algorithm
bool rayIntersectsTriangle(in vec3 rayOrigin, 
                           in vec3 rayDir, 
                           in vec3 p0,
                           in vec3 p1,
                           in vec3 p2,
                           out vec3 intersection)
{
    const float EPSILON = 0.0000001;
    vec3 edge1, edge2, h, s, q;
    float a,f,u,v;
    edge1 = p1 - p0;
    edge2 = p2 - p0;
    h = cross(rayDir, edge2);
    a = dot(edge1, h);
    if (a > -EPSILON && a < EPSILON)
        return false;    // This ray is parallel to this triangle.
    f = 1.0/a;
    s = rayOrigin - p0;
    u = f * (dot(s, h));
    if (u < 0.0 || u > 1.0)
        return false;
    q = cross(s, edge1);
    v = f * dot(rayDir, q);
    if (v < 0.0 || u + v > 1.0)
        return false;
    // At this stage we can compute t to find out where the intersection point is on the line.
    float t = f * dot(edge2, q);
    if (t > EPSILON) // ray intersection
    {
        intersection = rayOrigin + rayDir * t;
        return true;
    }
    else // This means that there is a line intersection but not a ray intersection.
        return false;
}

bool intersectionCheck(in Ray ray, out int triangleIdx, out vec3 intersectionP) {
    vec3 p0 = vec3(0.0);
    vec3 p1 = vec3(0.0);
    vec3 p2 = vec3(0.0);

    float minDist = FLT_MAX;

    for(int i = 0; i < u_TriangleCount; i++) {
        getTrianglePosition(i, p0, p1, p2);
        if(rayIntersectsTriangle(ray.origin, ray.direction, p0, p1, p2, intersectionP)) {
            float dist = length(intersectionP - ray.origin);
            if (dist <= minDist) {
                minDist = dist;
                triangleIdx = i;
            }
        }
    }

    if (minDist < FLT_MAX) {
        return true;
    } else {
        return false;
    }

}

// pay attention to rays that didnt hit anything----------------
Ray castRay() {
    Ray ray;

    vec4 NDC = vec4(0.0, 0.0, 1.0, 1.0);
    // lower left corner is (0, 0) for Frag_Coord
    NDC.x = (gl_FragCoord.x / u_Width) * 2.0 - 1.0;
    NDC.y = (gl_FragCoord.y / u_Height) * 2.0 - 1.0;

    vec4 pixelWorldPos = u_ViewInv * u_ProjInv * (NDC * u_Far);
    vec3 rayDir = normalize(pixelWorldPos.xyz - u_Camera); 
    ray.hitLight = false;
    ray.remainingBounces = MAX_DEPTH;    
    

    // ray.direction = rayDir;
    // ray.origin = u_Camera;    
    // ray.color = vec3(1.0);

    vec3 worldPos = texture(u_Pos, fs_UV).xyz;
    vec3 worldNor = texture(u_Nor, fs_UV).xyz;
    vec3 albedo = texture(u_Albedo, fs_UV).xyz;
    ray.direction = reflect(rayDir, worldNor);
    ray.origin = worldPos + worldNor * EPSILON;
    ray.color = albedo;

    // for screen pixels where no geometry
    if (length(worldNor) <= 0.0) {
        ray.remainingBounces = 0;
    } else {
        ray.remainingBounces = MAX_DEPTH;
    }
    

    return ray;
}

void shadeRay(in int triangleIdx, in vec3 intersectionP, out Ray ray) {    
    vec3 normal = getTriangleNormal(triangleIdx);
    vec4 material = getTriangleMaterial(triangleIdx);
    vec4 baseColor = getTriangleBaseColor(triangleIdx);

    float random = noise2d(fs_UV.x, fs_UV.y);  
    float specularProp = material[0];
    float diffuseProp = material[1];    
    float emittance = material[3];    

    
    // hit light
    if (emittance > 0.0) {
        ray.remainingBounces = 0;   
        ray.hitLight = true; 
        ray.color *= (baseColor.xyz * emittance);    
    
        return;
    }

    if (random < specularProp) {    // shoot specular ray
        ray.direction = reflect(ray.direction, normal);
        ray.origin = intersectionP + normal * EPSILON;
        ray.color *= baseColor.xyz;                
        ray.remainingBounces--;   
        
    } else if (random < diffuseProp) {  // shoot a diffuse ray    
        ray.direction = calculateRandomDirectionInHemisphere(normal);
        ray.origin = intersectionP + normal * EPSILON;
        ray.color *= baseColor.xyz;                
        ray.remainingBounces--;   
         
        // ray.remainingBounces = 0;    

    }

}

void raytrace(inout Ray ray) {
    int triangleIdx = -1;
    vec3 intersectionP = vec3(0.0);
    // if hit any triangle
    if (intersectionCheck(ray, triangleIdx, intersectionP)) {        
        shadeRay(triangleIdx, intersectionP, ray);
    } else {
        // ray.color = missColor;
        ray.remainingBounces = 0;
    }
}




void main()
{
   float ambient_term = 0.5;    
    
   Ray ray = castRay();
   out_Col = vec4(1.0);

   while (ray.remainingBounces > 0) {
        raytrace(ray);
   }

   if (!ray.hitLight) {
    //    ray.color = missColor;
        ray.color *= ambient_term;  // add ambien term manually
   }

   vec3 albedo = texture(u_Albedo, fs_UV).xyz;
    out_Col = vec4(ray.color, 1.0);   
    // out_Col = vec4((ray.color + albedo) * 0.5, 1.0);
    


}