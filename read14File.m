function varargout = read14File(varargin)

%% READ14FILE Reads-in a fort.14 mesh file
%   fort14 = read14File() reads-in a user-selected fort.14 file and saves
%   it as a structure with the following fields:
%
%     » fort14.MeshID = the mesh identification string (<= 24 characters).
%     » fort14.Triangulation = the mesh saved as a MATLAB® triangulation 
%       object. To obtain a plot of the triangulation use 
%       > triplot(fort14.Triangulation)
%     » fort14.Polyshape = the mesh boundary saved as a MATLAB® polyshape 
%       object. To obtain a plot of the boundary polyshape use
%       > plot(fort14.Polyshape)
%     » fort14.BoundarySegments = the mesh boundary segment information 
%       saved in a table with the following variables (where N is the num-
%       ber of boundary segments):
%          - BoundarySegments.Type = an N by 1 categorical array 
%            indicating the boundary segment type, either 'Elevation' or 
%            'NormalFluxTypeK' where K is an integer value defining the 
%            particular normal-flux boundary type; see http://adcirc.org/ 
%            for details.
%          - BoundarySegments.Nodes = a 1 by N cell array, where cell i 
%            stores the node numbers that make up boundary segment i.
%          - BoundarySegments.Data = a 1 by N cell array, where cell i 
%            stores additional node-based boundary data associated with 
%            some normal-flux boundary types. If no additional data is 
%            associated with a particular boundary type, the cell is empty.
%
%   fort14 = read14File(fileName) same as above but reads in the fort.14
%   file specified by fileName.
%
%   fort14 = read14File(fileName,boundaryData), where boundaryData is  
%   binary indicating to read (1) or not read (0) the mesh boundary data. 
%   The default is to read-in the boundary data. 
%   
%   NOTE: See the ADCIRC documention at https://adcirc.org/ for more
%   details on the format of the input/output files.
%

%% Open the fort.14 file ==================================================
if nargin > 0 
    if ~isa(varargin{1},'char')
        getFile = 2;
    else
        getFile = 0;
        vFN = @(x)validateattributes(x,{'char'},{'nonempty'});
        vBD = @(x)validateattributes(x,{'double'},{'scalar','binary'});
        ip = inputParser;
        ip.addOptional('fileName','',vFN);
        ip.addOptional('boundaryData',1,vBD);
        ip.parse(varargin{:});
        ip.Results;
        file = ip.Results.fileName;
        boundaryData = ip.Results.boundaryData;
    end
else
    getFile = 1;
end
if getFile > 0
    [filename, varargout{2}] = uigetfile({'*.14; *.grd'},...
        'Select a .14 or .grd file');
    file = [varargout{2},filename];  
    if getFile ~= 2
        boundaryData = questdlg('Read-in the boundary data?');
        switch boundaryData
            case 'Yes'
                boundaryData = 1;
            case 'No'
                boundaryData = 0;
        end
    else
        boundaryData = 0;
    end
end
fileID = fopen(file,'r');
%% Set up the progress bar ================================================
if getFile == 2
    ui = true;
    progressBar = uiprogressdlg(varargin{1}.UIFigure,'Title','Please Wait'); 
    varargout{3} = progressBar;
else
    ui = false;
    wait = waitbar(0,'Please wait...');
end

%% Create the fort14 structure ============================================
fort14 = struct('MeshID',[],'Triangulation',[],'Polyshape',[],...
    'BoundarySegments',[]);

%% Read in the mesh =======================================================
% Read in the header info
fort14.MeshID = fgetl(fileID);
% Read in the number of elements and the number of nodes
numberOfElems = fscanf(fileID,'%u',1);
numberOfNodes = fscanf(fileID,'%u %* [^\n]',1);
% Update the progress bar
progressBar.Message = 'Reading the mesh point list.....'; 
progressBar.Value = 0.25;
if ~ui
    waitbar(progressBar.Value,wait,progressBar.Message);
end
% Read in the point list
points = textscan(fileID,'%f %f %f %f %*[^\n]',numberOfNodes);
% Update the progress bar
progressBar.Message = 'Reading the mesh connectivity list.....';
progressBar.Value = 0.50;
if ~ui
    waitbar(progressBar.Value,wait,progressBar.Message);
end
% Read in the element connectivity
connectivityList = cell2mat(textscan(fileID,'%f %f %f %f %f %*[^\n]',...
    numberOfElems));

%% Contruct the Matlab triangulation
fort14.Triangulation = triangulation(connectivityList(:,3:5),...
    points{2},points{3},points{4});

%% Construct a polyshape of the boundary ==================================
fort14.Polyshape = boundaryshape(triangulation(...
    fort14.Triangulation.ConnectivityList,...
    fort14.Triangulation.Points(:,1:2))); 

%% If boundary data is not requested close and return
if ~boundaryData
    % Close waitbar and file
    if ~ui
        close(wait)
    end
    fclose(fileID);
    varargout{1} = fort14;
    return
end
%% Read in the boundary data ==============================================
% Update the progress bar
progressBar.Message = 'Reading and processing the mesh boundary data.....';
progressBar.Value = 0.75;
if ~ui
    waitbar(progressBar.Value,wait,progressBar.Message);
end
% Read in the number of elevation-specified boundary segments
elevSegments = cell2mat(textscan(fileID,'%u %*[^\n]',2));
% Loop over the elevation-specified boundary segments
if ~isempty(elevSegments)
    for i = 1:elevSegments(1)
        Segment = textscan(fileID,'%f %*[^\n]',1);
        BoundarySegments.Type{i} = 'Elevation';
        BoundarySegments.Nodes{i} = fscanf(fileID,'%u',Segment{1});
        BoundarySegments.Data{i} = [];       
    end
else
    elevSegments = 0;
end
% Read in the number of flux-specified boundary segments
FluxSegments = cell2mat(textscan(fileID,'%u %*[^\n]',2));
% Loop over the flux-specified boundary segments
if ~isempty(FluxSegments)
    for i = elevSegments(1)+1:elevSegments(1)+FluxSegments(1)
        Segment = textscan(fileID,'%f %f %*[^\n]',1);
        BoundarySegments.Type{i} = ...
            ['NormalFluxType',num2str(Segment{2})];
        switch Segment{2}
            case {0, 1, 10, 11, 20, 21, 30} % No-normal flow ==============
                BoundarySegments.Nodes{i} = ...
                    fscanf(fileID,'%u',Segment{1});
                BoundarySegments.Data{i} = [];   
            case {2, 102, 12, 112, 22, 122, 52 } % Non-zero normal flow ===
                BoundarySegments.Nodes{i} = ...
                    fscanf(fileID,'%u',Segment{1});
                BoundarySegments.Data{i} = [];   
            case {3, 13, 23} % External barriers ==========================                
                SegmentData = ...
                    textscan(fileID,'%u %f %f %*[^\n]',Segment{1});
                BoundarySegments.Nodes{i} = SegmentData{1};
                BoundarySegments.Data{i} = [SegmentData{2},SegmentData{3}];                                          
            case {18}
                SegmentData = textscan(fileID, '%f %f %*[^\n]',Segment{1});
                BoundarySegments.Nodes{i} = SegmentData{1};
                BoundarySegments.Data{i} = SegmentData{2} ;
            case {4, 24} % Internal barriers ==============================               
                SegmentData = textscan(fileID,'%u %f %f %f %f %*[^\n]',...
                    Segment{1});
                BoundarySegments.Nodes{i} = SegmentData{1};
                BoundarySegments.Data{i} = [SegmentData{2},...
                    SegmentData{3},SegmentData{4},SegmentData{5}];  
            case {5, 25} % Internal barrier with pipe =====================
                SegmentData = textscan(fileID,...
                    '%u %f %f %f %f %f %f %f %*[^\n]',Segment{1});
                BoundarySegments.Nodes{i} = SegmentData{1};
                BoundarySegments.Data{i} = [SegmentData{2},...
                    SegmentData{3},SegmentData{4},SegmentData{5},...
                    SegmentData{6},SegmentData{7},SegmentData{8}];
        end
    end
end

%% Create table to store boundary segment info ============================
fort14.BoundarySegments = table(categorical(BoundarySegments.Type'),...
    BoundarySegments.Nodes',BoundarySegments.Data','VariableNames',...
    {'Type','Nodes','Data'});
fort14.BoundarySegments.Properties.Description = 'Boundary Segment Data';
varargout{1} = fort14;

%% Close waitbar and file
if ~ui
    close(wait)
end
fclose(fileID);

end