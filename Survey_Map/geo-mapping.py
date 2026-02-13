import pandas as pd
import json
import os

# Read the Excel file
excel_path = "/Users/athamawardi/Desktop/Research-Projects/PSE_Pertamina/Survey_Map/lokasi_survei.xlsx"
df = pd.read_excel(excel_path, sheet_name='Calon-Survei')

# Parse coordinates from the "Koordinat" column
def parse_coordinates(coord_str):
    """Parse coordinates from string format 'lat,lon' to [lat, lon]"""
    if pd.isna(coord_str):
        return None
    try:
        parts = str(coord_str).strip().split(',')
        if len(parts) == 2:
            lat = float(parts[0].strip())
            lon = float(parts[1].strip())
            # Validate coordinates are reasonable for Indonesia
            if -15 <= lat <= 10 and 95 <= lon <= 145:
                return [lat, lon]
    except:
        pass
    return None

# Extract coordinates
df['coords'] = df['Koordinat'].apply(parse_coordinates)

# Filter out rows without valid coordinates
df_valid = df[df['coords'].notna()].copy()

print(f"Total rows: {len(df)}")
print(f"Rows with valid coordinates: {len(df_valid)}")

# Prepare marker data - separate SPBU and SPBUN
markers_data = []
spbu_count = 0
spbun_count = 0

for idx, row in df_valid.iterrows():
    # Get classification (SPBU or SPBUN)
    classification = str(row['SPBU/SPBUN']).strip() if pd.notna(row['SPBU/SPBUN']) else 'SPBUN'
    
    marker_info = {
        'lat': row['coords'][0],
        'lon': row['coords'][1],
        'no': row['No  Lembaga Penyalur'],
        'mor': row['MOR'],
        'classification': classification,
        'kawasan': row['Kawasan'] if pd.notna(row['Kawasan']) else '',
        'provinsi': row['Provinsi'] if pd.notna(row['Provinsi']) else '',
        'kabupaten': row['Kabupaten/Kota'] if pd.notna(row['Kabupaten/Kota']) else '',
        'kecamatan': row['Kecamatan'] if pd.notna(row['Kecamatan']) else '',
        'nama_badan_usaha': row['Nama Badan Usaha'] if pd.notna(row['Nama Badan Usaha']) else '',
        'badan_usaha': row['Badan Usaha'] if pd.notna(row['Badan Usaha']) else '',
        'tipe_spbun': row['Tipe SPBUN'] if pd.notna(row['Tipe SPBUN']) else '',
        'jenis_kepemilikan': row['Jenis Kepemilikan SPBUN'] if pd.notna(row['Jenis Kepemilikan SPBUN']) else '',
        'alamat': row['Alamat'] if pd.notna(row['Alamat']) else '',
        'pelabuhan': row['Pelabuhan (Pelabuhan & Non Pelabuhan)'] if pd.notna(row['Pelabuhan (Pelabuhan & Non Pelabuhan)']) else '',
        'laut_sungai': row['Laut/Sungai'] if pd.notna(row['Laut/Sungai']) else '',
        'spbu_sekitar': row['Keberadaan SPBU Sekitar (Km)'] if pd.notna(row['Keberadaan SPBU Sekitar (Km)']) else ''
    }
    markers_data.append(marker_info)
    
    if classification == 'SPBU':
        spbu_count += 1
    else:
        spbun_count += 1

print(f"SPBU locations: {spbu_count}")
print(f"SPBUN locations: {spbun_count}")

# Calculate center point (average of all coordinates)
if markers_data:
    avg_lat = sum(m['lat'] for m in markers_data) / len(markers_data)
    avg_lon = sum(m['lon'] for m in markers_data) / len(markers_data)
else:
    avg_lat, avg_lon = -2.5489, 118.0149  # Default center of Indonesia

# Read Indonesia GeoJSON
geojson_path = "/Users/athamawardi/Desktop/Research-Projects/PSE_Pertamina/Survey_Map/id.json"
with open(geojson_path, 'r', encoding='utf-8') as f:
    indonesia_geojson = json.load(f)

# Create HTML file
html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SPBUN Survey Map - Indonesia</title>
    
    <!-- Leaflet CSS -->
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
          integrity="sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY="
          crossorigin=""/>
    
    <!-- Leaflet JS -->
    <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"
            integrity="sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo="
            crossorigin=""></script>
    
    <!-- html2canvas for PNG export -->
    <script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
    
    <!-- SheetJS for Excel export -->
    <script src="https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js"></script>
    
    <style>
        body {{
            margin: 0;
            padding: 0;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }}
        
        #map {{
            width: 100%;
            height: 100vh;
        }}
        
        #table-view {{
            width: 100%;
            height: 100vh;
            display: none;
            padding: 20px;
            overflow: auto;
        }}
        
        .table-container {{
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            overflow: auto;
        }}
        
        table {{
            width: 100%;
            border-collapse: collapse;
        }}
        
        th, td {{
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }}
        
        th {{
            background-color: #3498db;
            color: white;
            position: sticky;
            top: 0;
            z-index: 10;
        }}
        
        tr:hover {{
            background-color: #f5f5f5;
        }}
        
        .toolbar {{
            position: fixed;
            top: 10px;
            left: 10px;
            z-index: 2000;
            display: flex;
            gap: 10px;
            flex-direction: column;
        }}
        
        .toolbar button {{
            padding: 10px 15px;
            background: white;
            border: 1px solid #ddd;
            border-radius: 5px;
            cursor: pointer;
            box-shadow: 0 2px 5px rgba(0,0,0,0.2);
            font-size: 14px;
            font-weight: 500;
        }}
        
        .toolbar button:hover {{
            background: #f8f9fa;
        }}
        
        .sidebar {{
            position: fixed;
            top: 0;
            right: -400px;
            width: 400px;
            height: 100vh;
            background: white;
            box-shadow: -2px 0 10px rgba(0,0,0,0.3);
            transition: right 0.3s ease;
            z-index: 1500;
            overflow-y: auto;
            overflow-x: hidden;
            padding: 20px;
            padding-bottom: 60px;
            visibility: hidden;
            pointer-events: none;
            box-sizing: border-box;
        }}
        
        .sidebar.open {{
            right: 0;
            visibility: visible;
            pointer-events: auto;
        }}
        
        .sidebar-toggle {{
            position: fixed;
            top: 10px;
            right: 10px;
            z-index: 1600;
            padding: 10px 15px;
            background: #3498db;
            color: white;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            box-shadow: 0 2px 5px rgba(0,0,0,0.2);
            font-size: 16px;
        }}
        
        .sidebar-toggle:hover {{
            background: #2980b9;
        }}
        
        .info-panel {{
            position: absolute;
            top: 10px;
            right: 10px;
            background: white;
            padding: 15px;
            border-radius: 5px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.3);
            z-index: 1000;
            max-width: 300px;
            font-size: 14px;
        }}
        
        .info-panel h3 {{
            margin-top: 0;
            color: #333;
            font-size: 18px;
        }}
        
        .info-panel p {{
            margin: 5px 0;
            color: #666;
        }}
        
        .filter-controls {{
            margin-top: 15px;
            padding-top: 15px;
            border-top: 1px solid #ddd;
        }}
        
        .filter-controls label {{
            display: flex;
            align-items: center;
            margin: 8px 0;
            cursor: pointer;
        }}
        
        .filter-controls input[type="checkbox"] {{
            margin-right: 8px;
            cursor: pointer;
        }}
        
        .legend {{
            margin-top: 15px;
            padding-top: 15px;
            border-top: 1px solid #ddd;
        }}
        
        .legend-item {{
            display: flex;
            align-items: center;
            margin: 5px 0;
        }}
        
        .legend-color {{
            width: 16px;
            height: 16px;
            border-radius: 50%;
            border: 2px solid white;
            box-shadow: 0 2px 5px rgba(0,0,0,0.3);
            margin-right: 8px;
        }}
        
        .custom-popup {{
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }}
        
        .custom-popup h4 {{
            margin-top: 0;
            color: #2c3e50;
            border-bottom: 2px solid #3498db;
            padding-bottom: 5px;
        }}
        
        .custom-popup .detail-row {{
            margin: 8px 0;
            padding: 5px;
            background: #f8f9fa;
            border-left: 3px solid #3498db;
            padding-left: 10px;
        }}
        
        .custom-popup .label {{
            font-weight: bold;
            color: #555;
        }}
        
        .custom-popup .value {{
            color: #333;
        }}
        
        .download-menu {{
            position: relative;
        }}
        
        .download-menu-btn {{
            padding: 10px 15px;
            background: white;
            border: 1px solid #ddd;
            border-radius: 5px;
            cursor: pointer;
            box-shadow: 0 2px 5px rgba(0,0,0,0.2);
            font-size: 14px;
            font-weight: 500;
            display: flex;
            align-items: center;
            gap: 8px;
        }}
        
        .download-menu-btn:hover {{
            background: #f8f9fa;
        }}
        
        .download-menu-btn::before {{
            content: '☰';
            font-size: 18px;
        }}
        
        .download-dropdown {{
            position: absolute;
            top: 100%;
            left: 0;
            margin-top: 5px;
            background: white;
            border: 1px solid #ddd;
            border-radius: 5px;
            box-shadow: 0 4px 10px rgba(0,0,0,0.2);
            min-width: 150px;
            z-index: 2100;
            display: none;
        }}
        
        .download-dropdown.show {{
            display: block;
        }}
        
        .download-dropdown button {{
            display: block;
            width: 100%;
            padding: 10px 15px;
            background: white;
            border: none;
            text-align: left;
            cursor: pointer;
            font-size: 13px;
        }}
        
        .download-dropdown button:hover {{
            background: #f8f9fa;
        }}
        
        .download-dropdown button:first-child {{
            border-top-left-radius: 5px;
            border-top-right-radius: 5px;
        }}
        
        .download-dropdown button:last-child {{
            border-bottom-left-radius: 5px;
            border-bottom-right-radius: 5px;
        }}
        
        .download-option {{
            display: none;
        }}
        
        .download-option.show {{
            display: block !important;
        }}
    </style>
</head>
<body>
    <div class="toolbar">
        <button onclick="toggleView()">Switch to Table</button>
        <div class="download-menu">
            <button class="download-menu-btn" onclick="toggleDownloadMenu()">Download</button>
            <div class="download-dropdown" id="download-dropdown">
                <button onclick="downloadPNG()" id="download-png-option" class="download-option">Download PNG</button>
                <button onclick="downloadCSV()" id="download-csv-option" class="download-option">Download CSV</button>
                <button onclick="downloadGeoJSON()" id="download-geojson-option" class="download-option">Download GeoJSON</button>
                <button onclick="downloadExcel()" id="download-excel-option" class="download-option">Download Excel</button>
            </div>
        </div>
    </div>
    
    <button class="sidebar-toggle" onclick="toggleSidebar()">☰ Options</button>
    
    <div id="map"></div>
    <div id="table-view">
        <div class="table-container">
            <table id="data-table">
                <thead id="table-head"></thead>
                <tbody id="table-body"></tbody>
            </table>
        </div>
    </div>
    
    <div class="sidebar" id="sidebar">
        <h3>SPBU/SPBUN Survey Map</h3>
        <p><strong>Total Locations:</strong> {len(markers_data)}</p>
        <p><strong>SPBU:</strong> {spbu_count} | <strong>SPBUN:</strong> {spbun_count}</p>
        
        <div class="legend">
            <strong>Legend:</strong>
            <div class="legend-item">
                <div class="legend-color" style="background-color: #e74c3c;"></div>
                <span>SPBU</span>
            </div>
            <div class="legend-item">
                <div class="legend-color" style="background-color: #3498db;"></div>
                <span>SPBUN</span>
            </div>
        </div>
        
        <div class="filter-controls">
            <strong>Filter:</strong>
            <label>
                <input type="checkbox" id="filter-spbu" checked>
                Show SPBU ({spbu_count})
            </label>
            <label>
                <input type="checkbox" id="filter-spbun" checked>
                Show SPBUN ({spbun_count})
            </label>
        </div>
        
        <p style="margin-top: 15px; margin-bottom: 20px; font-size: 12px; color: #999;">
            <strong>Hover</strong> over markers to see details<br/>
            <strong>Click</strong> markers for more information
        </p>
    </div>
    
    <script>
        // Global variables
        var currentView = 'map';
        var markersData = {json.dumps(markers_data, ensure_ascii=False)};
        var filteredMarkersData = markersData;
        
        function toggleView() {{
            if (currentView === 'map') {{
                currentView = 'table';
                document.getElementById('map').style.display = 'none';
                document.getElementById('table-view').style.display = 'block';
                document.querySelector('.toolbar button').textContent = 'Switch to Map';
                renderTable();
            }} else {{
                currentView = 'map';
                document.getElementById('map').style.display = 'block';
                document.getElementById('table-view').style.display = 'none';
                document.querySelector('.toolbar button').textContent = 'Switch to Table';
            }}
            updateDownloadMenu();
        }}
        
        // Initialize download menu
        updateDownloadMenu();
        
        function toggleSidebar() {{
            document.getElementById('sidebar').classList.toggle('open');
        }}
        
        function toggleDownloadMenu() {{
            var dropdown = document.getElementById('download-dropdown');
            dropdown.classList.toggle('show');
        }}
        
        function updateDownloadMenu() {{
            var pngOption = document.getElementById('download-png-option');
            var csvOption = document.getElementById('download-csv-option');
            var geojsonOption = document.getElementById('download-geojson-option');
            var excelOption = document.getElementById('download-excel-option');
            
            // Remove all show classes first
            pngOption.classList.remove('show');
            csvOption.classList.remove('show');
            geojsonOption.classList.remove('show');
            excelOption.classList.remove('show');
            
            if (currentView === 'map') {{
                pngOption.classList.add('show');
            }} else {{
                csvOption.classList.add('show');
                geojsonOption.classList.add('show');
                excelOption.classList.add('show');
            }}
        }}
        
        // Close download menu when clicking outside
        document.addEventListener('click', function(event) {{
            var downloadMenu = document.querySelector('.download-menu');
            var dropdown = document.getElementById('download-dropdown');
            if (downloadMenu && !downloadMenu.contains(event.target)) {{
                dropdown.classList.remove('show');
            }}
        }});
        
        function renderTable() {{
            var thead = document.getElementById('table-head');
            var tbody = document.getElementById('table-body');
            
            // Clear existing content
            thead.innerHTML = '';
            tbody.innerHTML = '';
            
            if (filteredMarkersData.length === 0) {{
                tbody.innerHTML = '<tr><td colspan="15" style="text-align: center;">No data to display</td></tr>';
                return;
            }}
            
            // Create header
            var headerRow = document.createElement('tr');
            var headers = ['No', 'Classification', 'MOR', 'Kawasan', 'Provinsi', 'Kabupaten/Kota', 'Kecamatan', 
                          'Nama Badan Usaha', 'Badan Usaha', 'Tipe SPBUN', 'Jenis Kepemilikan', 
                          'Alamat', 'Pelabuhan', 'Laut/Sungai', 'SPBU Sekitar', 'Latitude', 'Longitude'];
            headers.forEach(function(header) {{
                var th = document.createElement('th');
                th.textContent = header;
                headerRow.appendChild(th);
            }});
            thead.appendChild(headerRow);
            
            // Create rows
            filteredMarkersData.forEach(function(data) {{
                var row = document.createElement('tr');
                var values = [
                    data.no || '',
                    data.classification || '',
                    data.mor || '',
                    data.kawasan || '',
                    data.provinsi || '',
                    data.kabupaten || '',
                    data.kecamatan || '',
                    data.nama_badan_usaha || '',
                    data.badan_usaha || '',
                    data.tipe_spbun || '',
                    data.jenis_kepemilikan || '',
                    data.alamat || '',
                    data.pelabuhan || '',
                    data.laut_sungai || '',
                    data.spbu_sekitar || '',
                    data.lat || '',
                    data.lon || ''
                ];
                values.forEach(function(value) {{
                    var td = document.createElement('td');
                    td.textContent = value;
                    row.appendChild(td);
                }});
                tbody.appendChild(row);
            }});
        }}
        
        function downloadPNG() {{
            // Close dropdown
            document.getElementById('download-dropdown').classList.remove('show');
            
            if (currentView !== 'map') {{
                alert('Please switch to map view to download PNG');
                return;
            }}
            
            // Hide UI elements before capturing
            var toolbar = document.querySelector('.toolbar');
            var sidebar = document.getElementById('sidebar');
            var sidebarToggle = document.querySelector('.sidebar-toggle');
            var downloadDropdown = document.getElementById('download-dropdown');
            
            var toolbarDisplay = toolbar ? toolbar.style.display : '';
            var sidebarVisibility = sidebar ? sidebar.style.visibility : '';
            var sidebarToggleDisplay = sidebarToggle ? sidebarToggle.style.display : '';
            
            if (toolbar) toolbar.style.display = 'none';
            if (sidebar) sidebar.style.visibility = 'hidden';
            if (sidebarToggle) sidebarToggle.style.display = 'none';
            if (downloadDropdown) downloadDropdown.classList.remove('show');
            
            // Wait a bit for UI to hide
            setTimeout(function() {{
                html2canvas(document.getElementById('map'), {{
                    useCORS: true,
                    logging: false,
                    width: document.getElementById('map').offsetWidth,
                    height: document.getElementById('map').offsetHeight,
                    ignoreElements: function(element) {{
                        return element.classList.contains('toolbar') || 
                               element.classList.contains('sidebar') || 
                               element.classList.contains('sidebar-toggle') ||
                               element.classList.contains('download-menu') ||
                               element.classList.contains('download-dropdown') ||
                               element.classList.contains('leaflet-control-layers');
                    }}
                }}).then(function(canvas) {{
                    // Restore UI elements
                    if (toolbar) toolbar.style.display = toolbarDisplay || '';
                    if (sidebar) sidebar.style.visibility = sidebarVisibility || '';
                    if (sidebarToggle) sidebarToggle.style.display = sidebarToggleDisplay || '';
                    
                    var link = document.createElement('a');
                    link.download = 'spbun_map.png';
                    link.href = canvas.toDataURL('image/png');
                    link.click();
                }});
            }}, 100);
        }}
        
        function downloadCSV() {{
            // Close dropdown
            document.getElementById('download-dropdown').classList.remove('show');
            
            var csv = 'No,Classification,MOR,Kawasan,Provinsi,Kabupaten/Kota,Kecamatan,Nama Badan Usaha,Badan Usaha,Tipe SPBUN,Jenis Kepemilikan,Alamat,Pelabuhan,Laut/Sungai,SPBU Sekitar,Latitude,Longitude\\n';
            
            filteredMarkersData.forEach(function(data) {{
                csv += [
                    data.no || '',
                    data.classification || '',
                    data.mor || '',
                    '"' + (data.kawasan || '').replace(/"/g, '""') + '"',
                    '"' + (data.provinsi || '').replace(/"/g, '""') + '"',
                    '"' + (data.kabupaten || '').replace(/"/g, '""') + '"',
                    '"' + (data.kecamatan || '').replace(/"/g, '""') + '"',
                    '"' + (data.nama_badan_usaha || '').replace(/"/g, '""') + '"',
                    '"' + (data.badan_usaha || '').replace(/"/g, '""') + '"',
                    '"' + (data.tipe_spbun || '').replace(/"/g, '""') + '"',
                    '"' + (data.jenis_kepemilikan || '').replace(/"/g, '""') + '"',
                    '"' + (data.alamat || '').replace(/"/g, '""') + '"',
                    '"' + (data.pelabuhan || '').replace(/"/g, '""') + '"',
                    '"' + (data.laut_sungai || '').replace(/"/g, '""') + '"',
                    data.spbu_sekitar || '',
                    data.lat || '',
                    data.lon || ''
                ].join(',') + '\\n';
            }});
            
            var blob = new Blob([csv], {{ type: 'text/csv;charset=utf-8;' }});
            var link = document.createElement('a');
            link.href = URL.createObjectURL(blob);
            link.download = 'spbun_data.csv';
            link.click();
        }}
        
        function downloadGeoJSON() {{
            // Close dropdown
            document.getElementById('download-dropdown').classList.remove('show');
            
            var geojson = {{
                type: 'FeatureCollection',
                features: filteredMarkersData.map(function(data) {{
                    return {{
                        type: 'Feature',
                        geometry: {{
                            type: 'Point',
                            coordinates: [data.lon, data.lat]
                        }},
                        properties: {{
                            no: data.no,
                            classification: data.classification,
                            mor: data.mor,
                            kawasan: data.kawasan,
                            provinsi: data.provinsi,
                            kabupaten: data.kabupaten,
                            kecamatan: data.kecamatan,
                            nama_badan_usaha: data.nama_badan_usaha,
                            badan_usaha: data.badan_usaha,
                            tipe_spbun: data.tipe_spbun,
                            jenis_kepemilikan: data.jenis_kepemilikan,
                            alamat: data.alamat,
                            pelabuhan: data.pelabuhan,
                            laut_sungai: data.laut_sungai,
                            spbu_sekitar: data.spbu_sekitar
                        }}
                    }};
                }})
            }};
            
            var blob = new Blob([JSON.stringify(geojson, null, 2)], {{ type: 'application/json' }});
            var link = document.createElement('a');
            link.href = URL.createObjectURL(blob);
            link.download = 'spbun_data.geojson';
            link.click();
        }}
        
        function downloadExcel() {{
            // Close dropdown
            document.getElementById('download-dropdown').classList.remove('show');
            
            var ws_data = [];
            
            // Header row
            ws_data.push(['No', 'Classification', 'MOR', 'Kawasan', 'Provinsi', 'Kabupaten/Kota', 'Kecamatan', 
                         'Nama Badan Usaha', 'Badan Usaha', 'Tipe SPBUN', 'Jenis Kepemilikan', 
                         'Alamat', 'Pelabuhan', 'Laut/Sungai', 'SPBU Sekitar', 'Latitude', 'Longitude']);
            
            // Data rows
            filteredMarkersData.forEach(function(data) {{
                ws_data.push([
                    data.no || '',
                    data.classification || '',
                    data.mor || '',
                    data.kawasan || '',
                    data.provinsi || '',
                    data.kabupaten || '',
                    data.kecamatan || '',
                    data.nama_badan_usaha || '',
                    data.badan_usaha || '',
                    data.tipe_spbun || '',
                    data.jenis_kepemilikan || '',
                    data.alamat || '',
                    data.pelabuhan || '',
                    data.laut_sungai || '',
                    data.spbu_sekitar || '',
                    data.lat || '',
                    data.lon || ''
                ]);
            }});
            
            var wb = XLSX.utils.book_new();
            var ws = XLSX.utils.aoa_to_sheet(ws_data);
            XLSX.utils.book_append_sheet(wb, ws, 'SPBUN Data');
            XLSX.writeFile(wb, 'spbun_data.xlsx');
        }}
        
        // Update filtered data when filters change
        function updateFilteredData() {{
            var showSPBU = document.getElementById('filter-spbu').checked;
            var showSPBUN = document.getElementById('filter-spbun').checked;
            
            filteredMarkersData = markersData.filter(function(data) {{
                if (data.classification === 'SPBU' && !showSPBU) return false;
                if (data.classification === 'SPBUN' && !showSPBUN) return false;
                return true;
            }});
            
            if (currentView === 'table') {{
                renderTable();
            }}
        }}
        
        console.log('Starting map initialization...');
        
        try {{
            // Initialize map centered on Indonesia
            var map = L.map('map').setView([{avg_lat}, {avg_lon}], 5);
            console.log('Map created');
            
            // Create base layers
            var osmLayer = L.tileLayer('https://{{s}}.tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png', {{
                attribution: '© OpenStreetMap contributors',
                maxZoom: 19
            }});
            
            var satelliteLayer = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{{z}}/{{y}}/{{x}}', {{
                attribution: '© Esri &mdash; Source: Esri, Maxar, GeoEye, Earthstar Geographics, CNES/Airbus DS, USDA, USGS, AeroGRID, IGN, and the GIS User Community',
                maxZoom: 19
            }});
            
            // Add default layer
            osmLayer.addTo(map);
            console.log('Tile layer added');
            
            // Add layer control - position it on top-right but below the sidebar toggle
            var baseMaps = {{
                "Map": osmLayer,
                "Satellite": satelliteLayer
            }};
            
            var layerControl = L.control.layers(baseMaps, null, {{
                position: 'topright'
            }}).addTo(map);
            
            // Adjust position to be below the sidebar toggle button
            var layerControlElement = document.querySelector('.leaflet-top.leaflet-right');
            if (layerControlElement) {{
                layerControlElement.style.top = '60px';
            }}
            
            console.log('Layer control added');
            
            // Add Indonesia GeoJSON boundary - load asynchronously to not block rendering
            setTimeout(function() {{
                try {{
                    var indonesiaGeoJSON = {json.dumps(indonesia_geojson)};
                    console.log('GeoJSON loaded, features:', indonesiaGeoJSON.features ? indonesiaGeoJSON.features.length : 'unknown');
                    
                    var indonesiaLayer = L.geoJSON(indonesiaGeoJSON, {{
                        style: {{
                            fillColor: '#e8f4f8',
                            fillOpacity: 0.3,
                            color: '#0066cc',
                            weight: 2,
                            opacity: 0.8
                        }},
                        onEachFeature: function(feature, layer) {{
                            layer.on({{
                                mouseover: function(e) {{
                                    var layer = e.target;
                                    layer.setStyle({{
                                        fillOpacity: 0.5,
                                        weight: 3
                                    }});
                                }},
                                mouseout: function(e) {{
                                    indonesiaLayer.resetStyle(e.target);
                                }}
                            }});
                        }}
                    }}).addTo(map);
                    console.log('Indonesia boundary layer added');
                }} catch (geoError) {{
                    console.error('Error loading GeoJSON:', geoError);
                    console.log('Continuing without Indonesia boundary overlay');
                }}
            }}, 500);
        
            
            // Marker data is already in global scope
            console.log('Markers data loaded:', markersData.length, 'locations');
            
            // Create custom icons
            var spbuIcon = L.divIcon({{
                className: 'spbu-marker',
                html: '<div style="background-color: #e74c3c; width: 12px; height: 12px; border-radius: 50%; border: 2px solid white; box-shadow: 0 2px 5px rgba(0,0,0,0.3);"></div>',
                iconSize: [12, 12],
                iconAnchor: [6, 6]
            }});
            
            var spbunIcon = L.divIcon({{
                className: 'spbun-marker',
                html: '<div style="background-color: #3498db; width: 12px; height: 12px; border-radius: 50%; border: 2px solid white; box-shadow: 0 2px 5px rgba(0,0,0,0.3);"></div>',
                iconSize: [12, 12],
                iconAnchor: [6, 6]
            }});
            
            // Add markers - separate arrays for filtering
            var allMarkers = [];
            var spbuMarkers = [];
            var spbunMarkers = [];
            
            markersData.forEach(function(data) {{
                try {{
                    // Choose icon based on classification
                    var icon = (data.classification === 'SPBU') ? spbuIcon : spbunIcon;
                    var classification = data.classification || 'SPBUN';
                    
                    var marker = L.marker([data.lat, data.lon], {{
                        icon: icon
                    }});
                    
                    // Create popup content based on classification
                    var title = classification + ' #' + data.no;
                    var popupContent = '<div class="custom-popup">' +
                        '<h4>' + title + '</h4>' +
                        '<div class="detail-row"><span class="label">MOR:</span> <span class="value">' + data.mor + '</span></div>' +
                        '<div class="detail-row"><span class="label">Nama Badan Usaha:</span> <span class="value">' + (data.nama_badan_usaha || '') + '</span></div>' +
                        '<div class="detail-row"><span class="label">Badan Usaha:</span> <span class="value">' + (data.badan_usaha || '') + '</span></div>';
                    
                    // Add SPBUN-specific fields only for SPBUN
                    if (classification === 'SPBUN') {{
                        popupContent += '<div class="detail-row"><span class="label">Tipe SPBUN:</span> <span class="value">' + (data.tipe_spbun || '') + '</span></div>' +
                            '<div class="detail-row"><span class="label">Jenis Kepemilikan:</span> <span class="value">' + (data.jenis_kepemilikan || '') + '</span></div>';
                    }}
                    
                    popupContent += '<div class="detail-row"><span class="label">Provinsi:</span> <span class="value">' + (data.provinsi || '') + '</span></div>' +
                        '<div class="detail-row"><span class="label">Kabupaten/Kota:</span> <span class="value">' + (data.kabupaten || '') + '</span></div>' +
                        '<div class="detail-row"><span class="label">Kecamatan:</span> <span class="value">' + (data.kecamatan || '') + '</span></div>' +
                        '<div class="detail-row"><span class="label">Alamat:</span> <span class="value">' + (data.alamat || '') + '</span></div>';
                    
                    // Add SPBUN-specific fields
                    if (classification === 'SPBUN') {{
                        popupContent += '<div class="detail-row"><span class="label">Pelabuhan:</span> <span class="value">' + (data.pelabuhan || '') + '</span></div>' +
                            '<div class="detail-row"><span class="label">Laut/Sungai:</span> <span class="value">' + (data.laut_sungai || '') + '</span></div>';
                    }}
                    
                    popupContent += '<div class="detail-row"><span class="label">SPBU Sekitar:</span> <span class="value">' + (data.spbu_sekitar || '') + ' Km</span></div>' +
                        '<div class="detail-row"><span class="label">Koordinat:</span> <span class="value">' + data.lat + ', ' + data.lon + '</span></div>' +
                        '</div>';
                    
                    // Create tooltip (hover)
                    var tooltipContent = '<strong>' + title + '</strong><br/>' +
                        (data.nama_badan_usaha || '') + '<br/>' +
                        (data.provinsi || '') + ' - ' + (data.kabupaten || '');
                    
                    marker.bindPopup(popupContent, {{
                        maxWidth: 400,
                        className: 'custom-popup-container'
                    }});
                    
                    marker.bindTooltip(tooltipContent, {{
                        permanent: false,
                        direction: 'top',
                        offset: [0, -10],
                        className: 'custom-tooltip'
                    }});
                    
                    // Add to map initially
                    marker.addTo(map);
                    
                    // Store in appropriate arrays
                    allMarkers.push(marker);
                    if (classification === 'SPBU') {{
                        spbuMarkers.push(marker);
                    }} else {{
                        spbunMarkers.push(marker);
                    }}
                }} catch (markerError) {{
                    console.error('Error adding marker:', markerError, data);
                }}
            }});
            
            console.log('Markers added - SPBU:', spbuMarkers.length, 'SPBUN:', spbunMarkers.length);
            
            // Filter functionality
            function updateMarkerVisibility() {{
                var showSPBU = document.getElementById('filter-spbu').checked;
                var showSPBUN = document.getElementById('filter-spbun').checked;
                
                spbuMarkers.forEach(function(marker) {{
                    if (showSPBU) {{
                        if (!map.hasLayer(marker)) {{
                            marker.addTo(map);
                        }}
                    }} else {{
                        if (map.hasLayer(marker)) {{
                            map.removeLayer(marker);
                        }}
                    }}
                }});
                
                spbunMarkers.forEach(function(marker) {{
                    if (showSPBUN) {{
                        if (!map.hasLayer(marker)) {{
                            marker.addTo(map);
                        }}
                    }} else {{
                        if (map.hasLayer(marker)) {{
                            map.removeLayer(marker);
                        }}
                    }}
                }});
                
                // Update filtered data for table/download
                updateFilteredData();
            }}
            
            // Add event listeners to checkboxes
            document.getElementById('filter-spbu').addEventListener('change', updateMarkerVisibility);
            document.getElementById('filter-spbun').addEventListener('change', updateMarkerVisibility);
            
            // Fit map to show all markers
            if (allMarkers.length > 0) {{
                try {{
                    var group = new L.featureGroup(allMarkers);
                    map.fitBounds(group.getBounds().pad(0.1));
                    console.log('Map bounds fitted to markers');
                }} catch (boundsError) {{
                    console.error('Error fitting bounds:', boundsError);
                }}
            }}
            
            console.log('Map initialized successfully with', markersData.length, 'locations');
        }} catch (error) {{
            console.error('Error initializing map:', error);
            alert('Error loading map. Please check the browser console for details.');
        }}
    </script>
</body>
</html>
"""

# Write HTML file
output_path = "/Users/athamawardi/Desktop/Research-Projects/PSE_Pertamina/Survey_Map/spbun_map.html"
with open(output_path, 'w', encoding='utf-8') as f:
    f.write(html_content)

print(f"\nInteractive map created successfully!")
print(f"Output file: {output_path}")
print(f"\nOpen the HTML file in your browser to view the map.")
