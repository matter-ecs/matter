<div align="center">
	<h1>
    <img src=".moonwave/static/logo.svg" alt="Matter" width="600" />
  </h1>
</div>
<div align="center">
	<a href="https://github.com/matter-ecs/matter/actions/workflows/ci.yaml">
		<img src="https://github.com/matter-ecs/matter/actions/workflows/ci.yaml/badge.svg" alt="CI status">
	</a>
  <a href="https://matter-ecs.github.io/matter/">
		<img src="https://github.com/matter-ecs/matter/actions/workflows/docs.yaml/badge.svg" alt="Docs status">
	</a>
  <a href="https://discord.gg/6cvzthZC4X">
    <img src="https://dcbadge.vercel.app/api/server/6cvzthZC4X?style=flat" alt="OSS Discord">
  </a>
</div>
<br>

**Matter** is a modern ECS library for _[Roblox]_.

[roblox]: https://www.roblox.com/

## Installation

Matter can be installed with [Wally] by including it as a dependency in your
`wally.toml` file.

```toml
Matter = "matter-ecs/matter@0.8.4"
```

## Migration

If you're currently using the scope `evaera/matter`, prior versions are the same
package. You can migrate by changing your `wally.toml` file to use the scope
`matter-ecs/matter`.

## Building

Before building, you'll need to install all dependencies using [Wally].

You can then sync or build the project with [Rojo]. Matter contains several
project files with different builds of the project. The `default.project.json`
is the package build. The `example.project.json` is the example game build.

[rojo]: https://rojo.space/
[wally]: https://wally.run/

## Contributing

Contributions are welcome, please make a pull request! Check out our
[contribution] guide for further information.

Please read our [code of conduct] when getting involved.

[contribution]: CONTRIBUTING.md
[code of conduct]: CODE_OF_CONDUCT.md

## Project Legacy

Matter was originally pioneered by [@evaera](https://www.github.com/evaera). She
laid the robust foundation for the work we continue today.

## License

Matter is free software available under the MIT license. See the [license] for
details.

[license]: LICENSE.md
