#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "tokamak.h"

// Controlled fixture, not Bontago's undisclosed settings.
static int tick = 0, contact_tick = -1;
static void on_contact(neCollisionInfo &) { if (contact_tick < 0) contact_tick = tick; }
int main(int argc, char **argv) {
    if (argc > 1 && std::strcmp(argv[1], "stack") && std::strcmp(argv[1], "drop")) return 2;
    const bool stack = argc > 1 && std::strcmp(argv[1], "stack") == 0;
    const float edge = 0.98f, height = argc > 2 ? float(std::atof(argv[2])) : 2.0f;
    const float interval = argc > 3 ? float(std::atof(argv[3])) : 2.0f;
    const float gap = argc > 4 ? float(std::atof(argv[4])) : 0.3f;
    if (!(height > 0 && interval > 0 && interval * 2 < 10 && gap > 0)) return 2;
    neSimulatorSizeInfo sizes;
    sizes.rigidBodiesCount = 3; sizes.animatedBodiesCount = 1;
    sizes.geometriesCount = 4; sizes.overlappedPairsCount = 6;
    neV3 gravity; gravity.Set(0, -9.8f, 0);
    neSimulator *sim = neSimulator::CreateSimulator(sizes, nullptr, &gravity);
    if (!sim) return 3;
    float friction, restitution; sim->GetMaterial(0, friction, restitution);
    sim->GetCollisionTable()->Set(0, 0, neCollisionTable::RESPONSE_IMPULSE_CALLBACK);
    sim->SetCollisionCallback(on_contact);
    neAnimatedBody *floor = sim->CreateAnimatedBody();
    floor->AddGeometry()->SetBoxSize(30, 1, 30); floor->UpdateBoundingInfo();
    neV3 p; p.Set(0, -0.5f, 0); floor->SetPos(p);
    neRigidBody *bodies[3] = {}; int count = 0;
    auto spawn = [&](int index) {
        neRigidBody *b = sim->CreateRigidBody(); bodies[count++] = b;
        b->AddGeometry()->SetBoxSize(edge, edge, edge); b->UpdateBoundingInfo();
        b->SetMass(1); b->SetInertiaTensor(neBoxInertiaTensor(edge, edge, edge, 1));
        p.Set(0, edge * 0.5f + (stack ? index * edge + (index ? gap * edge : 0) : height * edge), 0);
        b->SetPos(p);
    };
    spawn(0);
    const int interval_ticks = std::fmax(1, int(std::round(interval * 60)));
    const int observation = stack ? 2 * interval_ticks : 0;
    float peak = -1e10f, drift = 0; int sleep = -1; bool asleep = false;
    const char *trace_path = argc > 5 ? argv[5] : nullptr;
    FILE *trace = trace_path ? std::fopen(trace_path, "w") : nullptr;
    if (trace) std::fprintf(trace, "tick,time_s,count,top_x_m,top_y_m,top_z_m,all_idle\n");
    for (tick = 1; tick <= 600; ++tick) {
        if (stack && count < 3 && tick >= interval_ticks * count) spawn(count);
        sim->Advance(1.0f / 60.0f, 1);
        asleep = true; for (int i = 0; i < count; ++i) asleep = asleep && bool(bodies[i]->IsIdle());
        neV3 pos = bodies[count-1]->GetPos();
        if (tick >= observation) {
            drift = std::fmax(drift, std::sqrt(pos[0]*pos[0] + pos[2]*pos[2]));
            if (asleep && sleep < 0) sleep = tick;
        }
        if (!stack && contact_tick >= 0) peak = std::fmax(peak, pos[1]);
        if (trace) std::fprintf(trace, "%d,%.6f,%d,%.9g,%.9g,%.9g,%d\n", tick, tick/60.0, count, pos[0], pos[1], pos[2], asleep);
    }
    if (trace) std::fclose(trace);
    neV3 final = bodies[count-1]->GetPos();
    float rebound = contact_tick < 0 ? 0 : std::fmax(0.0f, (peak - edge*0.5f)/edge);
    std::printf("{\"baseline\":\"Tokamak source defaults\",\"mode\":\"%s\",\"duration_s\":10,\"physics_hz\":60,\"cube_edge_m\":%.9g,\"mass_kg\":1,\"gravity_m_s2\":9.8,\"friction\":%.9g,\"restitution\":%.9g,\"linear_damp\":%.9g,\"angular_damp\":%.9g,\"all_asleep\":%s,\"first_asleep_s\":%.9g,\"max_lateral_drift_cubes\":%.9g,\"top_final_y_cubes\":%.9g", stack ? "stack":"drop", edge, friction, restitution, bodies[0]->GetLinearDamping(), bodies[0]->GetAngularDamping(), asleep?"true":"false", sleep < 0 ? -1.0 : (sleep-observation)/60.0, drift/edge, (final[1]-edge*0.5f)/edge);
    if (stack) std::printf(",\"stack_count\":3,\"stack_interval_s\":%.9g,\"placement_gap_cubes\":%.9g", interval, gap);
    else std::printf(",\"drop_height_cubes\":%.9g,\"first_contact_s\":%.9g,\"rebound_height_cubes\":%.9g,\"rebound_to_drop_ratio\":%.9g", height, contact_tick < 0 ? -1.0 : contact_tick/60.0, rebound, rebound/height);
    std::puts("}"); neSimulator::DestroySimulator(sim);
}
