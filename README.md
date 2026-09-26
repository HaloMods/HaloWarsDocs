# Halo Wars Documentation and Tools releases

[![CI](https://github.com/HaloMods/HaloWarsDocs/actions/workflows/continuous_integration.yml/badge.svg?branch=main)](https://github.com/HaloMods/HaloWarsDocs/actions/workflows/continuous_integration.yml)

* [Halo Wars 1 Docs](HaloWars1/README.md)
* [Halo Wars 2 Docs](HaloWars2/README.md)

## PhxTools build and dependency policy

Run aggregate commands from the `PhxTools` directory. `Directory.Packages.props` owns the requested package versions for the selected modules, while `global.json` selects the .NET SDK, Microsoft Testing Platform, and `MSTest.Sdk`. Component projects keep versionless `PackageReference` items and must not add project-authored `VersionOverride` values.

Committed `packages.lock.json` files remain beside executable, test, benchmark, and Roslyn component projects. CI restores those approved lock owners in locked mode; ordinary class libraries do not own adjacent locks.

After an intentional dependency change, regenerate the canonical RID-less Release locks:

```powershell
Set-Location PhxTools
dotnet restore .\PhxTools.sln -p:Configuration=Release -p:Platform=AnyCPU -p:ContinuousIntegrationBuild=false --force-evaluate
```

Validate both CI configurations:

```powershell
foreach ($configuration in 'Debug', 'Release') {
    dotnet restore .\PhxTools.sln -p:Configuration=$configuration -p:Platform=AnyCPU -p:ContinuousIntegrationBuild=true
    dotnet build .\PhxTools.sln -p:Configuration=$configuration -p:Platform=AnyCPU --no-restore -m
    dotnet test .\PhxTools.sln -p:Configuration=$configuration -p:Platform=AnyCPU --no-build --no-restore --verbosity normal -- --filter "TestCategory!=ExcludedFromAppveyor"
}
```

RID-specific publishes write uncommitted locks under `_obj` so they cannot rewrite adjacent RID-less locks:

```powershell
dotnet publish .\Games\PhxStudio\PhxStudio\PhxStudio.csproj -p:Configuration=Release -p:Platform=AnyCPU -r win-x64 --self-contained true -p:PublishSingleFile=true
```

Review central catalog changes, regenerated lock diffs, component commits, and superproject gitlink updates as separate compatibility evidence.
