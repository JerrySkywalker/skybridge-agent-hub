function skybridge_matlab_startup_doctor(outputDir)
% SKYBRIDGE_MATLAB_STARTUP_DOCTOR Fixed startup diagnostic for Bootstrap Alpha.
% It performs one no-toolbox calculation and writes only sanitized outputs.

if nargin ~= 1
    error('skybridge:invalidArgs', 'Expected outputDir.');
end

if ~ischar(outputDir) && ~isstring(outputDir)
    error('skybridge:invalidOutputDir', 'outputDir must be a string.');
end

outputDir = char(outputDir);
if exist(outputDir, 'dir') ~= 7
    mkdir(outputDir);
end

score = 2 * 3 / 500;
metricsPath = fullfile(outputDir, 'doctor_metrics.csv');
fid = fopen(metricsPath, 'w');
if fid < 0
    error('skybridge:metricsOpenFailed', 'Unable to open doctor_metrics.csv for writing.');
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'eta,h_km,P,score\n');
fprintf(fid, '2,500,3,%.12g\n', score);
clear cleanup;

summary = struct( ...
    'schema', 'skybridge.matlab_doctor_summary.v1', ...
    'matlab_version_summary', version, ...
    'minimal_compute_ok', true, ...
    'metrics_path', metricsPath, ...
    'raw_stdout_included', false, ...
    'raw_stderr_included', false, ...
    'token_printed', false);

writeJson(fullfile(outputDir, 'doctor_summary.json'), summary);
end

function writeJson(path, value)
fid = fopen(path, 'w');
if fid < 0
    error('skybridge:jsonOpenFailed', 'Unable to open output JSON file.');
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', jsonencode(value));
clear cleanup;
end
