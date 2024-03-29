//
//  ViewController.swift
//  Routing
//
//  Created by Chris Eidhof on 18.10.18.
//  Copyright © 2018 objc.io. All rights reserved.
//

import UIKit
import MapKit

struct Presenter {
    private var tracks: [Track:MKPolygon] = [:]
    var graph: Graph?
    
    func track(for polygon: MKPolygon) -> Track? {
        return tracks.first(where: { (track, poly) in poly == polygon })?.key
    }
    
    mutating func add(_ track: Track) -> MKPolygon {
        let coords = track.clCoordinates
        let polygon = MKPolygon(coordinates: coords, count: coords.count)
        tracks[track] = polygon
        return polygon
    }
    
    var boundingRect: MKMapRect {
        let boundingRects = tracks.values.map { $0.boundingMapRect }
        return boundingRects.reduce(MKMapRect.null) { $0.union($1) }
    }
    
    var tappedPoints: [Coordinate] = []
    
    mutating func tapped(_ coord2d: CLLocationCoordinate2D) -> [Coordinate]? {
        guard let g = graph else { return nil }
        let coord = Coordinate(coord2d)
        let distances = g.edges.keys.map { ($0, distance: $0.distance(to: coord) )}
        let (closest, _) = distances.min(by: { c1, c2 in
            c1.distance < c2.distance
        })!
        tappedPoints.append(closest)
        
        if tappedPoints.count >= 2 {
            return g.shortestPath(from: tappedPoints[tappedPoints.endIndex-2], to: tappedPoints[tappedPoints.endIndex-1])
        }
        return nil
    }
}

class ViewController: UIViewController {
    let mapView = MKMapView()
    var presenter = Presenter()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        mapView.delegate = self
        view.addSubview(mapView, constraints: [
            equal(\.leadingAnchor), equal(\.trailingAnchor),
            equal(\.topAnchor), equal(\.bottomAnchor)
        ])
        DispatchQueue.global(qos: .userInitiated).async {
            let tracks = Track.load()
            DispatchQueue.main.async {
                self.updateMapView(tracks)
                
                DispatchQueue.global(qos: .userInitiated).async {
                    let graph = measure("build graph", { buildGraph(tracks: tracks) })
                    DispatchQueue.main.async {
                        self.presenter.graph = graph
                    }
                }
            }
        }
        mapView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }
    
    func renderGraph(_ graph: Graph) {
        let startingPoint = graph.edges.keys.randomElement()!
        let steps = graph.debug_connectedVertices(vertex: startingPoint)
        
        func drawStep(_ remainder: ArraySlice<[(Coordinate, Coordinate)]>) {
            guard let step = remainder.first else { return }
            for edge in step {
                let line = MKPolyline(coordinates: [CLLocationCoordinate2D(edge.0), CLLocationCoordinate2D(edge.1)], count: 2)
                mapView.addOverlay(line)
            }
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.0001) {
                drawStep(remainder.dropFirst())
            }
        }
        
        drawStep(steps[...])
        
//        for (vertex, edges) in graph.edges {
//            for edge in edges {
//            }
//        }
    }
    
    @objc func tapped(_ recognizer: UITapGestureRecognizer) {
        let tapLoc = recognizer.location(in: mapView)
        let tapCoord = mapView.convert(tapLoc, toCoordinateFrom: mapView)
        if let shortestPath = presenter.tapped(tapCoord) {
            let coords = shortestPath.map { CLLocationCoordinate2D($0) }
            let line = MKPolyline(coordinates: coords, count: coords.count)
            mapView.addOverlay(line)
        }
    }
    
    func updateMapView(_ newTracks: [Track]) {
        for t in newTracks {
            let polygon = presenter.add(t)
            mapView.addOverlay(polygon)
        }
        let boundingRect = presenter.boundingRect
        mapView.setVisibleMapRect(boundingRect, edgePadding: UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10), animated: true)
    }
}

extension ViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let p = overlay as? MKPolygon {
            let track = presenter.track(for: p)!
            let r = MKPolygonRenderer(polygon: p)
            r.lineWidth = 1
            r.strokeColor = track.color.uiColor
            r.fillColor = track.color.uiColor.withAlphaComponent(0.2)
            return r
        } else if let l = overlay as? MKPolyline {
            let r = MKPolylineRenderer(polyline: l)
            r.lineWidth = 2
            r.strokeColor = .black
            return r
        } else {
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

extension Track {
    var clCoordinates: [CLLocationCoordinate2D] {
        return coordinates.map { CLLocationCoordinate2D($0.coordinate) }
    }
}

extension CLLocationCoordinate2D {
    init(_ coord: Coordinate) {
        self.init(latitude: coord.latitude, longitude: coord.longitude)
    }
    
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        return MKMapPoint(self).distance(to: MKMapPoint(other))
    }
}

extension Coordinate {
    func distance(to other: Coordinate) -> CLLocationDistance {
        return CLLocationCoordinate2D(self).distance(to: CLLocationCoordinate2D(other))
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        return (pow(other.x-x, 2) + pow(other.y-y, 2)).squareRoot()
    }
}
