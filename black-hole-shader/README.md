# Black hole shader

A real-time black hole for Unreal Engine 5. Starlight bends around it, a glowing disk of gas orbits it, and the side of the disk rushing toward you shines brighter and bluer than the side moving away.

![The black hole at a low angle: an orange accretion disk wraps around the black shadow, its far side bent up over the top.](https://paraminder-dhiman.github.io/images/black-hole/01-hero.jpg)

**Get it ready to use:** free on [Fab](https://www.fab.com/listings/a15ec3ff-d601-4c25-8338-f12082425b43), with a demo level and presets.
**How it works:** the full breakdown is on my [portfolio](https://paraminder-dhiman.github.io/black-hole-shader.html), with a [video](https://www.youtube.com/watch?v=U_VcXvOcbJQ).

## What's in this repo

| Folder | What it is |
|---|---|
| `Material/` | The material and its material instance |
| `Shaders/` | The HLSL inside the material's custom node, as plain text so changes are easy to read |

This repo holds the shader's source, not a full Unreal project. For a ready-made project with the demo level, use the Fab version.

## Requirements

Unreal Engine 5.8. Version 1.0 was built in 5.4.

## Use it

1. Copy the `Material` folder into your project's `Content` folder, with Unreal closed.
2. Open the project. Add a sphere to the level and assign the material instance to it.
3. Scale the sphere up so it surrounds the area the black hole should cover. The effect moves and scales with the actor.
4. Adjust the material instance's parameters.

To change the shader code, edit the custom node inside the material. The file in `Shaders/` is a copy for reading and tracking changes.

## How it works

Every pixel of the sphere marches a ray toward the black hole. Each step bends the ray using the exact light-bending equation for a non-spinning (Schwarzschild) black hole, with leapfrog steps that stay stable on tight orbits. Inside the disk, the ray samples the gas and lights it with a short shadow ray toward the centre. A ray either falls in, which leaves the pixel black, or escapes, and its bent direction is used to look up the sky, so any sky you use is lensed correctly.

Doppler beaming, gravitational redshift and blackbody colour sit on top as optional layers, each with a 0 to 1 slider. The defaults are physically based, and every artistic control from 1.0 is still there.

## Parameters

The material instance groups its parameters by what an artist would reach for:

- **Accretion Disk** · ring texture, density, inner and outer radius
- **Fog** · fog density, height and falloff
- **Light** · colour, intensity and bias
- **Shadow** · shadow colour, density and step size
- **Doppler** · Doppler strength, physical colour and inner temperature
- **Black Hole** · mass, which also sets the event horizon
- **Background** · the sky that gets lensed
- **Animation** · orbit speed and bands
- **Quality** · step sizes, maximum steps and jitter

## Versions

- **2.0** (2026) · rebuilt around the exact bending equation, adaptive step sizes, fixes for long-standing artifacts, and physics layered on as optional controls
- **1.0** (2023) · the original, with approximate bending and fixed step sizes

A full rebuild for a spinning (Kerr) black hole was also tried. It was accurate, but it lost the lit-fog look that defines this shader, so 2.0 stayed with the version above and the Kerr code is kept here as an experiment.

## Known limits

- Built for one black hole per view. Several can be placed, but they don't lens each other.
- The disk's grain is cleaned up by temporal anti-aliasing (TAA). With anti-aliasing off it looks noisier.

## Credit

Version 1.0 was built by me. For 2.0, the physics and HLSL rewrite was developed with AI assistance, directed, tested and tuned by me in Unreal.

## Licence

[MIT](LICENSE) · use it in anything, commercial work included. A credit is appreciated but not required.
 