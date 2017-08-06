return lovr.graphics.newShader([[
  // Declare two variables that we are going to calculate in the vertex shader and send to the
  // fragment shader.
  out vec3 vertexPosition;
  out vec3 lightViewPosition;
  out vec3 rawNormal;
  out vec3 normalDirection;

  uniform vec3 lightPosition = vec3(-1000, 3000, -3000);
  uniform mat4 viewMat;

  vec4 position(mat4 projection, mat4 transform, vec4 vertex) {
    vec4 transformedVertex = lovrTransform * vec4(lovrPosition, 1.);

    vertexPosition = vec3(transformedVertex) / transformedVertex.w;
    lightViewPosition = vec3(viewMat * vec4(lightPosition, 1));
    rawNormal = lovrNormal;
    normalDirection = normalize(lovrNormalMatrix * lovrNormal);

    return projection * transform * vertex;
  }
]], [[
  // Declare the two variables that are sent to us by the vertex shader
  in vec3 vertexPosition;
  in vec3 lightViewPosition;
  in vec3 rawNormal;
  in vec3 normalDirection;

  uniform vec3 ambientColor = vec3(.2, .2, .2);
  uniform vec3 diffuseColor = vec3(.7, .7, .7);
  uniform vec3 specularColor = vec3(.3, .3, .3);

  vec4 color(vec4 graphicsColor, sampler2D image, vec2 uv) {
    vec3 lightDirection = normalize(lightViewPosition - vertexPosition);

    float diffuse = max(dot(lightDirection, normalDirection), 0);
    float specular = 0.;

    if (diffuse > 0.) {
      vec3 reflectDir = reflect(-lightDirection, normalDirection);
      vec3 viewDirection = normalize(-vertexPosition);

      float specularAngle = max(dot(reflectDir, viewDirection), 0.);
      specular = pow(specularAngle, 5.);
    }

    vec3 finalColor = pow(clamp(vec3(diffuse) * diffuseColor + vec3(specular) * specularColor, ambientColor, vec3(1.)), vec3(.4545));

    return vec4(finalColor, 1.) * graphicsColor * texture(image, uv);
  }
]])
