clear all;
result=process_cos_batch('example_data','example_results')
success=1;
function results = process_cos_batch(inputPath, outputDir)
%PROCESS_COS_BATCH Process COS I/Q files and save waterfall PNG figures.
%
% Usage:
%   results = process_cos_batch(inputFolder, outputFolder)
% All processing settings are defined inside this function below.
%
% The expected filename layout is:
%   M,256,7.100000_500.000000_26.100000,10_2_2,...
%   ^  ^    ^       ^         ^        ^ ^ ^
%   |  |    |       |         |        | | pulse width
%   |  |    |       |         |        | code width
%   |  |    |       |         |        code order
%   |  |    |       |         end frequency in MHz
%   |  |    |       step, usually kHz; the unit is inferred
%   |  |    start frequency in MHz
%   |  loop count
%   file type / mode
%
% The binary payload is assumed to be little-endian int16 I/Q samples:
%   [I1 Q1 I2 Q2 ...] for each loop, then each frequency.
%
% The original LocalCode multiplication is a circular correlation. This
% implementation evaluates the same correlation with FFTs, sums all loops
% before the inverse FFT, and processes frequencies in blocks.
%
% Background is estimated separately at each frequency using median power.
% A smooth gain suppresses background without a hard detection threshold,
% helping retain weak oblique-sounding traces. No continuity mask is applied.
% Each file produces one background-suppressed PNG using parula.
% This is background suppression for display, not a calibrated CFAR detector.

if nargin < 1 || isempty(inputPath)
    inputPath = uigetdir(pwd, 'Select COS data folder');
    if isequal(inputPath, 0)
        error('No input folder was selected.');
    end
end

if nargin < 2 || isempty(outputDir)
    if isfolder(inputPath)
        outputDir = fullfile(inputPath, 'png');
    else
        outputDir = fileparts(inputPath);
    end
end

% Internal settings. Place m31a.mat, ..., m1023a.mat beside this function.
options.Recursive = true;
options.BlockFrequencies = 16;
options.CodeDirectory = fileparts(mfilename('fullpath'));
options.Code = [];
options.BaselineRange = [];
options.NoiseSuppression = 2; % Smooth gain knee in noise-power units.
options.RangeBinKm = 7.68;
options.YLim = [5000 9000]; % Clipped to the available range below.
options.CLim = [-35 0]; % Leave more display range for weak traces.
options.DynamicRangeDb = options.CLim(1);
options.Precision = 'single';
options.Visible = 'off';
options.CloseFigure = true;
options.Overwrite = true;
options.PreserveSubfolders = false;
options.ReturnData = false;
options.PngResolution = 180;
options.FontSize = 16;
options.Verbose = true;

inputPath = char(inputPath);
outputDir = char(outputDir);
options.CodeDirectory = char(options.CodeDirectory);
options.Precision = lower(char(options.Precision));

if ~strcmp(options.Precision, 'single') && ...
        ~strcmp(options.Precision, 'double')
    error('Precision must be ''single'' or ''double''.');
end
if ~isscalar(options.BlockFrequencies) || ...
        options.BlockFrequencies < 1 || ...
        options.BlockFrequencies ~= floor(options.BlockFrequencies)
    error('BlockFrequencies must be a positive integer.');
end
if ~isempty(options.BaselineRange) && ...
        (~isnumeric(options.BaselineRange) || ...
        numel(options.BaselineRange) ~= 2 || ...
        any(~isfinite(options.BaselineRange)) || ...
        any(options.BaselineRange < 1) || ...
        any(options.BaselineRange ~= floor(options.BaselineRange)) || ...
        options.BaselineRange(1) > options.BaselineRange(2))
    error('BaselineRange must be empty or two increasing positive indices.');
end
if ~isnumeric(options.NoiseSuppression) || ...
        ~isscalar(options.NoiseSuppression) || ...
        ~isfinite(options.NoiseSuppression) || options.NoiseSuppression < 0
    error('NoiseSuppression must be a finite non-negative scalar.');
end
if ~isnumeric(options.CLim) || numel(options.CLim) ~= 2 || ...
        options.CLim(1) >= options.CLim(2)
    error('CLim must be an increasing two-element vector.');
end
if isempty(options.DynamicRangeDb)
    options.DynamicRangeDb = options.CLim(1);
end
if ~isfolder(outputDir)
    [created, message] = mkdir(outputDir);
    if ~created
        error('Unable to create output folder: %s', message);
    end
end

[files, rootDir] = findCosFiles(inputPath, options.Recursive);
if isempty(files)
    error('No .cos files were found under: %s', inputPath);
end

resultTemplate = struct( ...
    'FilePath', '', ...
    'OutputPNG', '', ...
    'Success', false, ...
    'ErrorMessage', '', ...
    'LoopCount', NaN, ...
    'CodeOrder', NaN, ...
    'CodeWidth', NaN, ...
    'PulseWidth', NaN, ...
    'NumFrequencyBins', NaN, ...
    'FrequencyStartMHz', NaN, ...
    'FrequencyStepMHz', NaN, ...
    'FrequencyEndMHz', NaN, ...
    'Timestamp', NaT, ...
    'FrequencyMHz', [], ...
    'DistanceKm', [], ...
    'AmpDb', []);
results = repmat(resultTemplate, numel(files), 1);

codeCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
successCount = 0;

for fileIndex = 1:numel(files)
    filePath = getFilePath(files(fileIndex), rootDir);
    results(fileIndex).FilePath = filePath;

    if options.Verbose
        fprintf('[%d/%d] %s\n', fileIndex, numel(files), files(fileIndex).name);
    end

    try
        metadata = parseCosFilename(files(fileIndex).name);
        metadata = inferFileLayout(metadata, files(fileIndex).bytes);

        results(fileIndex).LoopCount = metadata.loopCount;
        results(fileIndex).CodeOrder = metadata.codeOrder;
        results(fileIndex).CodeWidth = metadata.codeWidth;
        results(fileIndex).PulseWidth = metadata.pulseWidth;
        results(fileIndex).NumFrequencyBins = metadata.numFrequencyBins;
        results(fileIndex).FrequencyStartMHz = metadata.frequencyStartMHz;
        results(fileIndex).FrequencyStepMHz = metadata.frequencyStepMHz;
        results(fileIndex).FrequencyEndMHz = metadata.frequencyEndMHz;
        results(fileIndex).Timestamp = metadata.timestamp;

        code = getCodeSequence(metadata.codeOrder, options, codeCache);
        [ampDb, frequencyMHz, distanceKm] = processOneCosFile( ...
            filePath, metadata, code, options);

        outputPath = makeOutputPath( ...
            filePath, rootDir, outputDir, options, '');
        writeWaterfallPng( ...
            ampDb, frequencyMHz, distanceKm, outputPath, ...
            files(fileIndex).name, options);

        results(fileIndex).OutputPNG = outputPath;
        results(fileIndex).FrequencyMHz = frequencyMHz;
        results(fileIndex).DistanceKm = distanceKm;
        if options.ReturnData
            results(fileIndex).AmpDb = ampDb;
        end

        results(fileIndex).Success = true;
        successCount = successCount + 1;
    catch ME
        results(fileIndex).ErrorMessage = ME.message;
        warning('Skipping %s: %s', files(fileIndex).name, ME.message);
    end
end

if options.Verbose
    fprintf('Completed %d/%d COS files.\n', successCount, numel(files));
end
if successCount == 0
    error('No COS files were processed successfully.');
end

end


function [files, rootDir] = findCosFiles(inputPath, recursive)

if isfile(inputPath)
    fileInfo = dir(inputPath);
    if isempty(fileInfo)
        error('Input file does not exist: %s', inputPath);
    end
    files = fileInfo(1);
    rootDir = fileparts(inputPath);
    if isempty(rootDir)
        rootDir = pwd;
    end
    return;
end

if ~isfolder(inputPath)
    error('Input folder does not exist: %s', inputPath);
end

rootDir = inputPath;
if recursive
    files = dir(fullfile(inputPath, '**', '*.cos'));
else
    files = dir(fullfile(inputPath, '*.cos'));
end
files = files(~[files.isdir]);

if isempty(files)
    return;
end

fileNames = {files.name};
fileNamesLower = cellfun(@lower, fileNames, 'UniformOutput', false);
[~, sortIndex] = sort(fileNamesLower);
files = files(sortIndex);

end


function filePath = getFilePath(fileInfo, rootDir)

if isfield(fileInfo, 'folder') && ~isempty(fileInfo.folder)
    filePath = fullfile(fileInfo.folder, fileInfo.name);
else
    filePath = fullfile(rootDir, fileInfo.name);
end

end


function metadata = parseCosFilename(fileName)

numberPattern = '[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?';
expression = [ ...
    '^[^,]+,', ...
    '(?<loopCount>\d+),', ...
    '(?<frequencyStartMHz>', numberPattern, ')_', ...
    '(?<rawStep>', numberPattern, ')_', ...
    '(?<frequencyEndMHz>', numberPattern, '),', ...
    '(?<codeOrder>\d+)_', ...
    '(?<codeWidth>\d+)_', ...
    '(?<pulseWidth>\d+),', ...
    '(?<date>\d{8})_(?<time>\d{6})'];

tokens = regexp(fileName, expression, 'names', 'once');
if isempty(tokens)
    error(['Filename does not match the expected COS layout: ', fileName]);
end

metadata = struct();
metadata.loopCount = str2double(tokens.loopCount);
metadata.frequencyStartMHz = str2double(tokens.frequencyStartMHz);
metadata.rawStep = str2double(tokens.rawStep);
metadata.frequencyEndMHz = str2double(tokens.frequencyEndMHz);
metadata.codeOrder = str2double(tokens.codeOrder);
metadata.codeWidth = str2double(tokens.codeWidth);
metadata.pulseWidth = str2double(tokens.pulseWidth);

if any(~isfinite([ ...
        metadata.loopCount, metadata.frequencyStartMHz, ...
        metadata.rawStep, metadata.frequencyEndMHz, ...
        metadata.codeOrder, metadata.codeWidth, metadata.pulseWidth]))
    error('Filename contains a non-numeric parameter: %s', fileName);
end
if metadata.loopCount < 1 || metadata.loopCount ~= floor(metadata.loopCount)
    error('Invalid loop count in filename: %s', fileName);
end
if metadata.codeOrder < 1 || metadata.codeOrder ~= floor(metadata.codeOrder)
    error('Invalid code order in filename: %s', fileName);
end
if metadata.codeWidth < 1 || metadata.codeWidth ~= floor(metadata.codeWidth)
    error('Invalid code width in filename: %s', fileName);
end
if metadata.pulseWidth < 1 || metadata.pulseWidth ~= floor(metadata.pulseWidth)
    error('Invalid pulse width in filename: %s', fileName);
end
if metadata.rawStep <= 0 || ...
        metadata.frequencyEndMHz <= metadata.frequencyStartMHz
    error('Invalid frequency sweep in filename: %s', fileName);
end

timestampText = [tokens.date, '_', tokens.time];
metadata.timestamp = datetime( ...
    timestampText, 'InputFormat', 'yyyyMMdd_HHmmss');

channelToken = regexp(fileName, '(?i)ch_(-?\d+)', 'tokens', 'once');
if isempty(channelToken)
    metadata.channel = NaN;
else
    metadata.channel = str2double(channelToken{1});
end

end


function metadata = inferFileLayout(metadata, fileBytes)

codeLength = 2^metadata.codeOrder - 1;
samplesPerFrequency = metadata.loopCount * ...
    metadata.codeWidth * codeLength;
bytesPerFrequency = samplesPerFrequency * 2 * 2;

numFrequencyBins = double(fileBytes) / double(bytesPerFrequency);
if numFrequencyBins ~= floor(numFrequencyBins) || numFrequencyBins < 2
    error(['File size %.0f bytes is inconsistent with the filename ', ...
        'parameters.'], double(fileBytes));
end
metadata.numFrequencyBins = round(numFrequencyBins);

% The middle frequency field is commonly kHz, but some datasets use MHz
% or Hz. Choose the unit whose implied bin count matches the file size.
unitScales = [1, 1e-3, 1e-6, 1e-9];
candidateStepMHz = metadata.rawStep .* unitScales;
candidateBinCounts = 1 + ...
    (metadata.frequencyEndMHz - metadata.frequencyStartMHz) ./ ...
    candidateStepMHz;
relativeError = abs(candidateBinCounts - metadata.numFrequencyBins) ./ ...
    max(1, metadata.numFrequencyBins);
[bestError, bestIndex] = min(relativeError);

if bestError <= 1e-6
    metadata.frequencyStepMHz = candidateStepMHz(bestIndex);
    metadata.stepScaleToMHz = unitScales(bestIndex);
else
    % Keep processing possible when the name was rounded or manually edited.
    metadata.frequencyStepMHz = ...
        (metadata.frequencyEndMHz - metadata.frequencyStartMHz) / ...
        (metadata.numFrequencyBins - 1);
    metadata.stepScaleToMHz = NaN;
    warning(['Frequency step in the filename does not agree with the ', ...
        'binary file size. Using the file-derived step %.12g MHz.'], ...
        metadata.frequencyStepMHz);
end

metadata.frequencyMHz = metadata.frequencyStartMHz + ...
    (0:metadata.numFrequencyBins - 1) .* metadata.frequencyStepMHz;

end


function code = getCodeSequence(codeOrder, options, codeCache)

expectedLength = 2^codeOrder - 1;
if ~isempty(options.Code)
    code = options.Code(:);
    if numel(code) ~= expectedLength
        error('Provided Code has %d samples; expected %d.', ...
            numel(code), expectedLength);
    end
    code = cast(code, options.Precision);
    return;
end

codeName = sprintf('m%da', expectedLength);
cacheKey = [options.CodeDirectory, '|', codeName, '|', options.Precision];
if isKey(codeCache, cacheKey)
    code = codeCache(cacheKey);
    return;
end

candidatePaths = { ...
    fullfile(options.CodeDirectory, [codeName, '.mat']), ...
    which([codeName, '.mat']), ...
    which(codeName)};
sourcePath = '';
for k = 1:numel(candidatePaths)
    if ~isempty(candidatePaths{k}) && isfile(candidatePaths{k})
        sourcePath = candidatePaths{k};
        break;
    end
end
if isempty(sourcePath)
    error(['Unable to locate %s.mat. Put the M-sequence file in ', ...
        'CodeDirectory or add it to the MATLAB path.'], codeName);
end

loaded = load(sourcePath);
if isfield(loaded, 'code') && isnumeric(loaded.code)
    code = loaded.code;
else
    names = fieldnames(loaded);
    code = [];
    for k = 1:numel(names)
        candidate = loaded.(names{k});
        if isnumeric(candidate) && isvector(candidate)
            code = candidate;
            break;
        end
    end
    if isempty(code)
        error('No numeric code vector was found in %s.', sourcePath);
    end
end

code = code(:);
if numel(code) ~= expectedLength
    error(['%s contains %d samples; code order %d requires %d samples.'], ...
        sourcePath, numel(code), codeOrder, expectedLength);
end
if ~isreal(code) || any(~isfinite(code))
    error('The code in %s must be a finite real vector.', sourcePath);
end

code = cast(code, options.Precision);
codeCache(cacheKey) = code;

end


function [ampDb, frequencyMHz, distanceKm] = processOneCosFile( ...
        filePath, metadata, code, options)

codeLength = numel(code);
loopCount = metadata.loopCount;
codeWidth = metadata.codeWidth;
numFrequencyBins = metadata.numFrequencyBins;
samplesPerLoop = codeLength * codeWidth;
samplesPerFrequency = samplesPerLoop * loopCount;
outputLength = samplesPerLoop;

ampComplex = complex(zeros( ...
    numFrequencyBins, outputLength, options.Precision));
codeSpectrum = fft(code);
codeSpectrum = reshape(conj(codeSpectrum), codeLength, 1, 1);

[fid, message] = fopen(filePath, 'r', 'ieee-le');
if fid < 0
    error('Unable to open file: %s', message);
end
fileCleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

blockSize = min(options.BlockFrequencies, numFrequencyBins);
for firstFrequency = 1:blockSize:numFrequencyBins
    lastFrequency = min( ...
        firstFrequency + blockSize - 1, numFrequencyBins);
    blockCount = lastFrequency - firstFrequency + 1;
    valueCount = 2 * samplesPerFrequency * blockCount;

    raw = fread(fid, valueCount, 'int16=>single');
    if numel(raw) ~= valueCount
        error('Unexpected end of file while reading frequency block.');
    end

    iData = raw(1:2:end);
    qData = raw(2:2:end);
    iq = complex( ...
        reshape(iData, samplesPerLoop, loopCount, blockCount), ...
        reshape(qData, samplesPerLoop, loopCount, blockCount));
    clear raw iData qData

    for phase = 1:codeWidth
        phaseData = iq(phase:codeWidth:end, :, :);
        phaseData = reshape(phaseData, codeLength, loopCount, blockCount);

        % Correlation is linear, so loop accumulation can happen first.
        summedData = sum(phaseData, 2);
        summedData = reshape(summedData, codeLength, 1, blockCount);
        spectrum = fft(summedData, [], 1);
        correlation = ifft( ...
            bsxfun(@times, spectrum, codeSpectrum), [], 1);
        correlation = reshape( ...
            permute(correlation, [3 1 2]), blockCount, codeLength);

        ampComplex(firstFrequency:lastFrequency, phase:codeWidth:end) = ...
            correlation;
    end
    clear iq
end

% Median power is robust when most reference bins contain background.
% For complex Gaussian noise, median(power) / log(2) estimates mean power.
powerMap = abs(ampComplex).^2;
if isempty(options.BaselineRange)
    referencePower = powerMap;
else
    baselineStart = options.BaselineRange(1);
    baselineEnd = min(outputLength, options.BaselineRange(2));
    if baselineStart > baselineEnd
        error('BaselineRange is outside the available correlation bins.');
    end
    referencePower = powerMap(:, baselineStart:baselineEnd);
end
noisePower = median(referencePower, 2) ./ log(2);
noisePower = max(noisePower, eps(max(powerMap(:))));
relativePower = bsxfun(@rdivide, powerMap, noisePower);
% Continuous attenuation preserves weak samples instead of rejecting them.
% No range/frequency smoothing: narrow or sloping traces retain their shape.
gain = relativePower ./ max(relativePower + options.NoiseSuppression, ...
    realmin(options.Precision));
signalPower = relativePower .* gain.^2;

% All-zero input stays at the color floor instead of becoming a 0 dB image.
ampDb = repmat(cast(options.DynamicRangeDb, options.Precision), ...
    size(signalPower));
peakPower = max(signalPower(:));
if peakPower > 0
    positive = signalPower > 0;
    ampDb(positive) = max(10 .* log10(signalPower(positive) ./ peakPower), ...
        options.DynamicRangeDb);
end

frequencyMHz = metadata.frequencyMHz;
distanceKm = (1:outputLength) .* options.RangeBinKm;

end


function outputPath = makeOutputPath( ...
        filePath, rootDir, outputDir, options, suffix)

[~, baseName] = fileparts(filePath);
baseName = [baseName, suffix];
targetDir = outputDir;

if options.PreserveSubfolders
    sourceDir = fileparts(filePath);
    prefix = [rootDir, filesep];
    if strncmpi(sourceDir, prefix, numel(prefix))
        relativeDir = sourceDir(numel(prefix) + 1:end);
        if ~isempty(relativeDir)
            targetDir = fullfile(outputDir, relativeDir);
        end
    end
end

if ~isfolder(targetDir)
    [created, message] = mkdir(targetDir);
    if ~created
        error('Unable to create output folder: %s', message);
    end
end

outputPath = fullfile(targetDir, [baseName, '.png']);
if ~options.Overwrite
    outputPath = uniquePath(outputPath);
end

end


function outputPath = uniquePath(outputPath)

if ~isfile(outputPath)
    return;
end

[folder, baseName, extension] = fileparts(outputPath);
counter = 2;
while true
    candidate = fullfile(folder, ...
        sprintf('%s_%d%s', baseName, counter, extension));
    if ~isfile(candidate)
        outputPath = candidate;
        return;
    end
    counter = counter + 1;
end

end


function writeWaterfallPng( ...
        ampDb, frequencyMHz, distanceKm, outputPath, fileName, options)

figureHandle = figure( ...
    'Visible', char(options.Visible), ...
    'Color', 'w', ...
    'Name', fileName);

try
    axesHandle = axes('Parent', figureHandle);
    imagesc(axesHandle, frequencyMHz, distanceKm, ampDb');
    set(axesHandle, ...
        'YDir', 'normal', ...
        'FontSize', options.FontSize, ...
        'FontWeight', 'bold', ...
        'Box', 'on');
    xlabel(axesHandle, 'Frequency / MHz', ...
        'FontSize', options.FontSize, 'FontWeight', 'bold');
    ylabel(axesHandle, 'Group distance / km', ...
        'FontSize', options.FontSize, 'FontWeight', 'bold');
    title(axesHandle, fileName, 'Interpreter', 'none');
    xlim(axesHandle, [frequencyMHz(1), frequencyMHz(end)]);
    if ~isempty(options.YLim)
        rangeUpper = min(options.YLim(2), distanceKm(end));
        rangeLower = max(options.YLim(1), distanceKm(1));
        if rangeLower >= rangeUpper
            % Short codes may not reach the requested lower limit either.
            rangeLower = distanceKm(1);
            rangeUpper = distanceKm(end);
        end
        if rangeLower < rangeUpper
            ylim(axesHandle, [rangeLower rangeUpper]);
        end
    end
    caxis(axesHandle, options.CLim);
    colorbarHandle = colorbar(axesHandle);
    colorbarHandle.Label.String = 'Normalized background-relative power / dB';
    colorbarHandle.FontSize = options.FontSize;
    colormap(figureHandle, parula(256));

    drawnow;
    if exist('exportgraphics', 'file') == 2
        exportgraphics( ...
            figureHandle, outputPath, ...
            'Resolution', options.PngResolution);
    else
        print( ...
            figureHandle, outputPath, '-dpng', ...
            sprintf('-r%d', options.PngResolution));
    end
catch ME
    if options.CloseFigure && isgraphics(figureHandle)
        close(figureHandle);
    end
    rethrow(ME);
end

if options.CloseFigure && isgraphics(figureHandle)
    close(figureHandle);
end

end
