clear; close all; clc;

%% Plot settings
fontSize=15;
faceAlpha1=0.3;
faceAlpha2=1;
cMap=gjet(4);
patchColor=cMap(1,:);
markerSize=25;


%% Select artery lumen STL
[arteryFile, arteryPath] = uigetfile("*.stl", "Select artery lumen STL");
if isequal(arteryFile, 0)
    error("No artery STL selected");
end

arteryLumenPath = fullfile(arteryPath, arteryFile);


%% Preprocessing surface meshes
art = import_STL(arteryLumenPath); 
F0=art.solidFaces{1}; %Faces 
V0=art.solidVertices{1}; %Vertices 

% Centering (relative position unchanged)
center =  mean(V0,1);

Vc = V0 - center;

% Refine mesh before remeshing
nRefineOriginal = 1;

if nRefineOriginal>0
    for q=1:1:nRefineOriginal
        [F0,Vc]=subtri(F0,Vc,1); %Refine input mesh through sub-triangulation
    end
end

[F0,V0]=mergeVertices(F0,Vc); % Merging nodes


% Remeshing
optionStruct2.pointSpacing=0.8; %Set desired point spacing 
%optionStruct2.disp_on=0; % Turn off command window text display 
[Fn,Vn]=ggremesh(F0,V0,optionStruct2);

% Write remeshed STLs
    % arteries
[~, baseArt] = fileparts(arteryLumenPath);
outNameArt   = [baseArt '_remesh'];
remeshPathArt = fullfile(arteryPath, [outNameArt '.stl']);

patch2STL(remeshPathArt, Vn, Fn, [], outNameArt);


% Run python with remeshed STL - thickens lumen mesh to create lumen+wall
% mesh
pyrunfile("matlab2.py", lumenPath=remeshPathArt);


%% Import STL files - boundary meshes
% artery
lumenStruct  = import_STL(fullfile(arteryPath, outNameArt + "_lumen.stl"));
wallStruct = import_STL(fullfile(arteryPath, outNameArt + "_wall.stl"));


%% Create the boundaries of the mesh
%Access the data from the STL struct
F5=wallStruct.solidFaces{1}; %Faces
V5=wallStruct.solidVertices{1}; %Vertices
[F5,V5]=mergeVertices(F5,V5); % Merging nodes

F6=lumenStruct.solidFaces{1}; %Faces
V6=lumenStruct.solidVertices{1}; %Vertices
[F6,V6]=mergeVertices(F6,V6); % Merging nodes


%% Remesh the boundaries and join together
optionStruct3.pointSpacing=0.9; 

[F1,V1]=ggremesh(F5,V5,optionStruct3); % wall art
[F2,V2]=ggremesh(F6,V6,optionStruct3); % lumen art


%% Prepare regions and volumes

% Joining surface sets
[F,V,C]=joinElementSets({F1,F2},{V1,V2});

% Find interior points
[V_region1]=getInnerPoint({F1,F2},{V1,V2});
[V_region2]=getInnerPoint(F2,V2);

V_regions=[V_region1; V_region2];

% Volume parameters
[vol1]=tetVolMeanEst(F1,V1);
[vol2]=tetVolMeanEst(F2,V2);


regionTetVolumes=[vol1 vol2]; %Element volume settings
stringOpt='-pq1.2AaY'; %Tetgen options


%% Mesh using tet

%Create tetgen input structure
inputStruct.stringOpt=stringOpt; %Tetgen options
inputStruct.Faces=F; %Boundary faces
inputStruct.Nodes=V; %Nodes of boundary
inputStruct.faceBoundaryMarker=C;
inputStruct.regionPoints=V_regions; %Interior points for regions
%inputStruct.holePoints=V_holes; %Interior points for holes
inputStruct.regionA=regionTetVolumes; %Desired tetrahedral volume for each region

% Mesh model using tetrahedral elements using tetGen
[meshOutput]=runTetGen(inputStruct); %Run tetGen


E=meshOutput.elements; %The elements
V=meshOutput.nodes; %The vertices or nodes
CE=meshOutput.elementMaterialID; %Element material or region id
Fb=meshOutput.facesBoundary; %The boundary faces
Cb=meshOutput.boundaryMarker; %The boundary markers


% Map region IDs to positive consecutive property IDs
[uniqueCE,~,pid] = unique(CE);
[uCE,~,ic] = unique(CE);
counts = accumarray(ic,1);

T = table(uCE,counts);
disp(T)

%% Visualization

hf=figure;
subplot(1,2,1); hold on;
title('Input boundaries','FontSize',fontSize);
hp(1)=gpatch(Fb,V,Cb,'k',faceAlpha1);
hp(2)=plotV(V_regions,'r.','MarkerSize',markerSize);
%hp(3)=plotV(V_holes,'g.','MarkerSize',markerSize);
legend(hp,{'Input mesh','Interior point(s)','Hole point(s)'},'Location','NorthWestOutside');
axisGeom(gca,fontSize); camlight headlight;
colormap(cMap); icolorbar;

hs=subplot(1,2,2); hold on;
title('Tetrahedral mesh','FontSize',fontSize);

% Visualizing using |meshView|
optionStruct.hFig=[hf,hs];
meshView(meshOutput,optionStruct);

axisGeom(gca,fontSize);
gdrawnow;

%% Save as NASTRAN bulk file
P = V;
t = E;

[~, base] = fileparts(remeshPathArt);
[filenas,path] = uiputfile('*.nas','Choose filename',[base '.nas']);

fileID = fopen(fullfile(path,filenas), 'w');

% GRID entries
for m = 1:size(P, 1)
    fprintf(fileID, '%-8s%-8s%-8s%8s%8s%8s\n', ...
        'GRID', num2str(m, '%6d'), '', ...
        num2str(P(m, 1), '%9.2f'), ...
        num2str(P(m, 2), '%8.2f'), ...
        num2str(P(m, 3), '%8.2f'));
end

% CTETRA entries, PID, 4 grid numbers
for m = 1:size(t, 1)
     fprintf(fileID, '%-8s%-8s%-8s%8s%8s%8s%8s\n', ...
        'CTETRA', num2str(m, '%6d'), num2str(pid(m),5), ...
        num2str(t(m, 1), '%6d'), ...
        num2str(t(m, 2), '%6d'), ...
        num2str(t(m, 3), '%6d'), ...
        num2str(t(m, 4), '%6d'));
end

fclose(fileID);

disp('NASTRAN bulk file written successfully.');