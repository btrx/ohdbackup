using UnityEngine;
using UnityEngine.SceneManagement;

public class ButtonScript : MonoBehaviour
{
    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        
    }

    public void LoadSceneAR()
    {
        // "ARScene" is disabled in Build Settings (EditorBuildSettings.asset), so loading it
        // silently fails at runtime. Load the same scene the Museum1 card itself loads.
        SceneManager.LoadScene("ARScene3");

    }
}
