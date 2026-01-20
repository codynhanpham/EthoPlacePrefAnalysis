function pth = datasetConfigPath(profile)
%%DATASETCONFIGPATH Get the path to the custom dataset configuration file for a given profile.

arguments
    profile {mustBeTextScalar, mustBeMember(profile, ["default", "archive", "archive_zstd"])} = "default"
end

thisdir = fileparts(mfilename('fullpath'));

switch profile
    case "default"
        pth = fullfile(thisdir, 'resources', 'custom_default_dataset_configuration.json');
    case "archive"
        pth = fullfile(thisdir, 'resources', 'custom_archive_dataset_configuration.json');
    case "archive_zstd"
        pth = fullfile(thisdir, 'resources', 'custom_archive_zstd_dataset_configuration.json');
    otherwise
        warning('Unknown profile "%s". Using default dataset configuration path.', profile);
        pth = fullfile(thisdir, 'resources', 'custom_default_dataset_configuration.json');
end