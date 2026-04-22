function migrateLegacyCSVRefs2JSON(videoDir)
%%MIGRATELEGACYCSVREFS2JSON Upgrade legacy midpoint/midline CSV files to .ref.json in a folder.
%   graphics.migrateLegacyCSVRefs2JSON(videoDir) scans videoDir for legacy
%   *.midline.csv and *.midpoint.csv files and migrates each to its matching
%   <videoBase>.ref.json file. Existing JSON fields are preserved.
%
%   Conversion rules:
%       - <base>.midline.csv -> <base>.ref.json, field .midline.x/.midline.y
%       - <base>.midpoint.csv -> <base>.ref.json, field .midpoint.x/.midpoint.y
%   If a matching .ref.json already exists, the legacy CSV is deleted.

arguments
	videoDir {mustBeFolder}
end

upgradeMidlineCsvFiles(videoDir);
upgradeMidpointCsvFiles(videoDir);
warning('graphics:migrateLegacyCSVRefs2JSON:UpgradeComplete', 'Legacy CSV midline/midpoint reference files in "%s" have been upgraded to JSON format. Please check warnings for any issues during the upgrade process.', videoDir);

end


function upgradeMidlineCsvFiles(videoDir)
	csvFiles = dir(fullfile(videoDir, '*.midline.csv'));
	for i = 1:numel(csvFiles)
		csvPath = fullfile(videoDir, csvFiles(i).name);
		baseName = erase(csvFiles(i).name, '.midline.csv');
		refPath = fullfile(videoDir, strcat(baseName, '.ref.json'));

		if isfile(refPath)
			deleteLegacyCsv(csvPath, 'graphics:migrateLegacyCSVRefs2JSON:LegacyCleanupError');
			continue;
		end

		try
			lineData = readtable(csvPath);
			if all(ismember({'x', 'y'}, lineData.Properties.VariableNames)) && height(lineData) >= 2
				pointA = [lineData.x(1), lineData.y(1)];
				pointB = [lineData.x(2), lineData.y(2)];
				saveMidlineToRefJson(pointA, pointB, refPath);
				deleteLegacyCsv(csvPath, 'graphics:migrateLegacyCSVRefs2JSON:LegacyCleanupError');
			else
				warning('graphics:migrateLegacyCSVRefs2JSON:MidlineRefUpgrade', 'Skipping malformed legacy .midline.csv file during upgrade: %s', csvPath);
			end
		catch ME
			warning('graphics:migrateLegacyCSVRefs2JSON:MidlineRefUpgradeError', 'Error upgrading legacy .midline.csv file: %s\n%s', csvPath, ME.message);
		end
	end
end


function upgradeMidpointCsvFiles(videoDir)
	csvFiles = dir(fullfile(videoDir, '*.midpoint.csv'));
	for i = 1:numel(csvFiles)
		csvPath = fullfile(videoDir, csvFiles(i).name);
		baseName = erase(csvFiles(i).name, '.midpoint.csv');
		refPath = fullfile(videoDir, strcat(baseName, '.ref.json'));

		if isfile(refPath)
			deleteLegacyCsv(csvPath, 'graphics:migrateLegacyCSVRefs2JSON:LegacyCleanupError');
			continue;
		end

		try
			midpointData = readtable(csvPath);
			if all(ismember({'x', 'y'}, midpointData.Properties.VariableNames)) && height(midpointData) >= 1
				referencePoint = [midpointData.x(1), midpointData.y(1)];
				saveMidpointToRefJson(referencePoint, refPath);
				deleteLegacyCsv(csvPath, 'graphics:migrateLegacyCSVRefs2JSON:LegacyCleanupError');
			else
				warning('graphics:migrateLegacyCSVRefs2JSON:MidpointRefUpgrade', 'Skipping malformed legacy .midpoint.csv file during upgrade: %s', csvPath);
			end
		catch ME
			warning('graphics:migrateLegacyCSVRefs2JSON:MidpointRefUpgradeError', 'Error upgrading legacy .midpoint.csv file: %s\n%s', csvPath, ME.message);
		end
	end
end


function saveMidlineToRefJson(pointA, pointB, referenceLineFilePath)
	jsonData = struct();
	if isfile(referenceLineFilePath)
		try
			jsonData = jsondecode(fileread(referenceLineFilePath));
		catch ME
			warning('graphics:migrateLegacyCSVRefs2JSON:SaveLoadError', 'Error loading existing .ref.json file for midline merge: %s\nOverwriting midline field with migrated data.\n%s', referenceLineFilePath, ME.message);
		end
	end
	jsonData.midline.x = [pointA(1), pointB(1)];
	jsonData.midline.y = [pointA(2), pointB(2)];
	writeRefJson(referenceLineFilePath, jsonData);
end


function saveMidpointToRefJson(referencePoint, referencePointFilePath)
	jsonData = struct();
	if isfile(referencePointFilePath)
		try
			jsonData = jsondecode(fileread(referencePointFilePath));
		catch ME
			warning('graphics:migrateLegacyCSVRefs2JSON:SaveLoadError', 'Error loading existing .ref.json file for midpoint merge: %s\nOverwriting midpoint field with migrated data.\n%s', referencePointFilePath, ME.message);
		end
	end
	jsonData.midpoint.x = referencePoint(1);
	jsonData.midpoint.y = referencePoint(2);
	writeRefJson(referencePointFilePath, jsonData);
end


function writeRefJson(refPath, jsonData)
	fid = -1;
	try
		jsonText = jsonencode(jsonData);
		fid = fopen(refPath, 'w');
		if fid == -1
			warning('graphics:migrateLegacyCSVRefs2JSON:SaveError', 'Could not open file for writing: %s', refPath);
			return;
		end
		fwrite(fid, jsonText, 'char');
		fclose(fid);
	catch ME
		if fid ~= -1
			fclose(fid);
		end
		warning('graphics:migrateLegacyCSVRefs2JSON:SaveError', 'Error writing .ref.json file: %s\n%s', refPath, ME.message);
	end
end


function deleteLegacyCsv(csvPath, warningId)
	try
		delete(csvPath);
	catch ME
		warning(warningId, 'Could not delete legacy CSV file: %s\n%s', csvPath, ME.message);
	end
end
